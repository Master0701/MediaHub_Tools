param()

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot

$version = "0.1.0"
$modelId = "HuggingFaceTB/SmolVLM2-500M-Video-Instruct"
$revision = "7b375e1b73b11138ff12fe22c8f2822d8fe03467"

$source = Join-Path $repo "work\smolvlm2-model\model"
$metadataRoot = Join-Path $repo "packages\smolvlm2-model\current"
$toolRoot = Join-Path $repo "tools\smolvlm2-model"
$release = Join-Path $repo "release\smolvlm2-model"
$temp = Join-Path $repo "temp\smolvlm2-model-build"

$packageName = "SmolVLM2-500M-Video-Instruct-v$version.zip"
$packagePath = Join-Path $release $packageName

# Single ZIP - kein Multipart erforderlich

Write-Host "========================================"
Write-Host "SMOLVLM2 MODEL BUILD"
Write-Host "========================================"
Write-Host ""

foreach ($path in @(
    $source,
    $metadataRoot,
    $toolRoot
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Pfad fehlt: $path"
    }
}

$manifestPath = Join-Path $metadataRoot "manifest.json"
$versionPath = Join-Path $metadataRoot "VERSION"
$noticePath = Join-Path $toolRoot "THIRD_PARTY_NOTICE.md"

foreach ($path in @(
    $manifestPath,
    $versionPath,
    $noticePath
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Pflichtdatei fehlt: $path"
    }
}

$manifest = Get-Content `
    -LiteralPath $manifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

if ($manifest.tool -ne "smolvlm2-model") {
    throw "Falsches Tool im Manifest."
}

if ($manifest.version -ne $version) {
    throw "Manifest-Version stimmt nicht."
}

if ($manifest.model -ne $modelId) {
    throw "Falsches Modell im Manifest."
}

if ($manifest.revision -ne $revision) {
    throw "Falsche Modellrevision im Manifest."
}

if ($manifest.license -ne "Apache-2.0") {
    throw "Unerwartete Modelllizenz."
}

# ------------------------------------------------------------
# Quelldateien gegen Manifest prüfen
# ------------------------------------------------------------

Write-Host "=== QUELLDATEIEN PRUEFEN ==="

foreach ($entry in $manifest.files) {

    $path = Join-Path $source $entry.file

    if (-not (Test-Path -LiteralPath $path)) {
        throw "Modelldatei fehlt: $($entry.file)"
    }

    $file = Get-Item -LiteralPath $path

    if ([int64]$file.Length -ne [int64]$entry.size) {
        throw "Dateigroesse stimmt nicht: $($entry.file)"
    }

    $hash = (
        Get-FileHash `
            -LiteralPath $path `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ($hash -ne $entry.sha256.ToLowerInvariant()) {
        throw "SHA256 stimmt nicht: $($entry.file)"
    }

    Write-Host "OK - $($entry.file)"
}

# Keine unerwarteten Dateien zulassen.

$expected = @(
    $manifest.files |
        ForEach-Object {
            $_.file
        } |
        Sort-Object
)

$actual = @(
    Get-ChildItem `
        -LiteralPath $source `
        -File |
        ForEach-Object {
            $_.Name
        } |
        Sort-Object
)

$diff = Compare-Object $expected $actual

if ($diff) {
    $diff | Format-Table -AutoSize
    throw "Unerwartete oder fehlende Dateien im Modellordner."
}

# ------------------------------------------------------------
# Arbeitsbereiche
# ------------------------------------------------------------

if (Test-Path -LiteralPath $temp) {
    Remove-Item `
        -LiteralPath $temp `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $temp `
    -Force |
    Out-Null

New-Item `
    -ItemType Directory `
    -Path $release `
    -Force |
    Out-Null

# Alte SmolVLM2-Buildartefakte entfernen.

Get-ChildItem `
    -LiteralPath $release `
    -File `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "SmolVLM2-500M-Video-Instruct-*"
    } |
    Remove-Item -Force

# ------------------------------------------------------------
# Stage erzeugen
# ------------------------------------------------------------

$stage = Join-Path $temp "SmolVLM2-500M-Video-Instruct"

New-Item `
    -ItemType Directory `
    -Path $stage `
    -Force |
    Out-Null

$modelStage = Join-Path $stage "model"

New-Item `
    -ItemType Directory `
    -Path $modelStage `
    -Force |
    Out-Null

Write-Host ""
Write-Host "=== STAGE ERZEUGEN ==="

foreach ($entry in $manifest.files) {

    Copy-Item `
        -LiteralPath (Join-Path $source $entry.file) `
        -Destination $modelStage `
        -Force
}

Copy-Item `
    -LiteralPath $manifestPath `
    -Destination (Join-Path $stage "manifest.json") `
    -Force

Copy-Item `
    -LiteralPath $versionPath `
    -Destination (Join-Path $stage "VERSION") `
    -Force

Copy-Item `
    -LiteralPath $noticePath `
    -Destination (Join-Path $stage "THIRD_PARTY_NOTICE.md") `
    -Force

Copy-Item `
    -LiteralPath (Join-Path $repo "THIRD_PARTY_LICENSES.md") `
    -Destination (Join-Path $stage "THIRD_PARTY_LICENSES.md") `
    -Force

# ------------------------------------------------------------
# ZIP
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== ZIP ERZEUGEN ==="
Write-Host $packageName

Compress-Archive `
    -Path $stage `
    -DestinationPath $packagePath `
    -CompressionLevel Optimal `
    -Force

$packageFile = Get-Item -LiteralPath $packagePath

$packageHash = (
    Get-FileHash `
        -LiteralPath $packagePath `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$packageHashPath = "$packagePath.sha256"

[System.IO.File]::WriteAllText(
    $packageHashPath,
    "$packageHash  $packageName`r`n",
    [System.Text.Encoding]::ASCII
)

Write-Host ""
Write-Host "ZIP:"
Write-Host $packagePath
Write-Host "Groesse: $($packageFile.Length)"
Write-Host "SHA256:  $packageHash"

# ------------------------------------------------------------
# Release-Manifest erzeugen
# ------------------------------------------------------------

$releaseManifest = [ordered]@{
    tool = "smolvlm2-model"
    version = $version

    model = $modelId
    revision = $revision
    license = "Apache-2.0"

    package = $packageName
    size = [int64]$packageFile.Length
    sha256 = $packageHash
    multipart = $false
    parts = @()
    targets = @(
        "windows_compute",
        "raspberry_pi"
    )

    platforms = @(
        "windows-amd64",
        "linux-aarch64"
    )

    runtime_bundled = $false

    built_at_utc = (
        Get-Date
    ).ToUniversalTime().ToString("o")
}

$releaseManifestPath = Join-Path `
    $release `
    "smolvlm2-model-manifest.json"

$releaseManifest |
    ConvertTo-Json -Depth 10 |
    Set-Content `
        -LiteralPath $releaseManifestPath `
        -Encoding UTF8

# ------------------------------------------------------------
# Ausgabe
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== RELEASE-DATEIEN ==="

Get-ChildItem `
    -LiteralPath $release `
    -File |
    Sort-Object Name |
    Select-Object `
        Name,
        Length,
        @{
            Name = "MiB"
            Expression = {
                [math]::Round($_.Length / 1MB, 2)
            }
        } |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Paketmodus: Single ZIP"
Write-Host ""
Write-Host "========================================"
Write-Host "SMOLVLM2 BUILD ERFOLGREICH"
Write-Host "NOCH NICHTS HOCHGELADEN"
Write-Host "========================================"


