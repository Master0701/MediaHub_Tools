param(
    [switch]$PreflightOnly,
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot

$releaseRoot = Join-Path $repo "release\gliner-runtime"
$metadataRoot = Join-Path $repo "packages\gliner-runtime\current"

$manifestPath = Join-Path $metadataRoot "manifest.json"
$versionPath = Join-Path $metadataRoot "VERSION"
$licensePath = Join-Path $repo "THIRD_PARTY_LICENSES.md"

Write-Host "========================================"
Write-Host "GLINER RELEASE PREFLIGHT"
Write-Host "========================================"
Write-Host ""

foreach ($path in @(
    $releaseRoot,
    $manifestPath,
    $versionPath,
    $licensePath
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Pfad fehlt: $path"
    }
}

$version = (
    Get-Content `
        -LiteralPath $versionPath `
        -Raw `
        -Encoding UTF8
).Trim()

$manifest = Get-Content `
    -LiteralPath $manifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

if ($manifest.tool -ne "gliner-runtime") {
    throw "Falsches Tool im Manifest."
}

if ($manifest.version -ne $version) {
    throw "VERSION und Manifest stimmen nicht ueberein."
}

$tag = "gliner-v$version"

Write-Host "Version: $version"
Write-Host "Tag:     $tag"
Write-Host ""

# ------------------------------------------------------------
# CPU
# ------------------------------------------------------------

Write-Host "=== CPU PRUEFEN ==="

$cpu = $manifest.packages.cpu
$cpuPath = Join-Path $releaseRoot $cpu.package
$cpuHashPath = "$cpuPath.sha256"

foreach ($path in @($cpuPath, $cpuHashPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "CPU-Datei fehlt: $path"
    }
}

$cpuHash = (
    Get-FileHash `
        -LiteralPath $cpuPath `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

if ($cpuHash -ne $cpu.sha256.ToLowerInvariant()) {
    throw "CPU-Gesamthash stimmt nicht."
}

$cpuStoredHash = (
    Get-Content `
        -LiteralPath $cpuHashPath `
        -Raw `
        -Encoding ASCII
).Trim().Split()[0].ToLowerInvariant()

if ($cpuStoredHash -ne $cpuHash) {
    throw "CPU-SHA256-Datei stimmt nicht."
}

Write-Host "OK - CPU"

# ------------------------------------------------------------
# CUDA Multipart
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== CUDA MULTIPART PRUEFEN ==="

$cuda = $manifest.packages.cuda

if ($cuda.multipart -ne $true) {
    throw "CUDA ist im Manifest nicht multipart."
}

$parts = @($cuda.parts)

if ($parts.Count -lt 2) {
    throw "Zu wenige CUDA-Parts."
}

$assets = @(
    $cpuPath,
    $cpuHashPath
)

foreach ($entry in $parts) {

    $partPath = Join-Path $releaseRoot $entry.file
    $partHashPath = "$partPath.sha256"

    foreach ($path in @($partPath, $partHashPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "CUDA-Part-Datei fehlt: $path"
        }
    }

    $partFile = Get-Item -LiteralPath $partPath

    if ([int64]$partFile.Length -ne [int64]$entry.size) {
        throw "CUDA-Part-Groesse stimmt nicht: $($entry.file)"
    }

    if ($partFile.Length -ge 2GB) {
        throw "CUDA-Part ist >= 2 GiB: $($entry.file)"
    }

    $partHash = (
        Get-FileHash `
            -LiteralPath $partPath `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ($partHash -ne $entry.sha256.ToLowerInvariant()) {
        throw "CUDA-Part-SHA256 stimmt nicht: $($entry.file)"
    }

    $storedHash = (
        Get-Content `
            -LiteralPath $partHashPath `
            -Raw `
            -Encoding ASCII
    ).Trim().Split()[0].ToLowerInvariant()

    if ($storedHash -ne $partHash) {
        throw "CUDA-Part-Hashdatei stimmt nicht: $($entry.file)"
    }

    $assets += $partPath
    $assets += $partHashPath

    Write-Host "OK - $($entry.file)"
}

# ------------------------------------------------------------
# CUDA aus Parts rekonstruieren
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== CUDA REKONSTRUKTION PRUEFEN ==="

$tempRoot = Join-Path $repo "temp\gliner-release-preflight"

if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item `
        -LiteralPath $tempRoot `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $tempRoot `
    -Force |
    Out-Null

$rebuiltPath = Join-Path $tempRoot $cuda.package

$output = [System.IO.File]::Create($rebuiltPath)

try {
    foreach ($entry in $parts) {

        $partPath = Join-Path $releaseRoot $entry.file

        $input = [System.IO.File]::OpenRead($partPath)

        try {
            $input.CopyTo($output)
        }
        finally {
            $input.Dispose()
        }
    }
}
finally {
    $output.Dispose()
}

$rebuiltFile = Get-Item -LiteralPath $rebuiltPath

if ([int64]$rebuiltFile.Length -ne [int64]$cuda.size) {
    throw "Rekonstruierte CUDA-Groesse stimmt nicht."
}

$rebuiltHash = (
    Get-FileHash `
        -LiteralPath $rebuiltPath `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

if ($rebuiltHash -ne $cuda.sha256.ToLowerInvariant()) {
    throw "Rekonstruierter CUDA-Gesamthash stimmt nicht."
}

Write-Host "OK - CUDA bytegenau rekonstruierbar"
Write-Host "Groesse: $($rebuiltFile.Length)"
Write-Host "SHA256:  $rebuiltHash"

Remove-Item `
    -LiteralPath $tempRoot `
    -Recurse `
    -Force

# ------------------------------------------------------------
# Release Assets
# ------------------------------------------------------------

$assets += $manifestPath
$assets += $versionPath
$assets += $licensePath

Write-Host ""
Write-Host "=== SPAETERE RELEASE-ASSETS ==="

foreach ($asset in $assets) {
    Write-Host " - $asset"
}

$forbiddenCudaZip = Join-Path $releaseRoot $cuda.package

if ($assets -contains $forbiddenCudaZip) {
    throw "STOP: Grosse CUDA-ZIP ist in der Assetliste."
}

Write-Host ""
Write-Host "OK - grosse CUDA-ZIP wird NICHT hochgeladen."

# ------------------------------------------------------------
# GitHub CLI
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== GITHUB CLI ==="

$gh = Get-Command gh -ErrorAction SilentlyContinue

if ($null -eq $gh) {
    throw "GitHub CLI (gh) wurde nicht gefunden."
}

gh auth status

if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI ist nicht korrekt angemeldet."
}

Write-Host ""
Write-Host "OK - GitHub CLI angemeldet."

# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== GIT REMOTE ==="

$remote = (
    git remote get-url origin
).Trim()

if ($LASTEXITCODE -ne 0) {
    throw "Git origin konnte nicht gelesen werden."
}

Write-Host $remote

if ($remote -notmatch 'Master0701/MediaHub_Tools(?:\.git)?$') {
    throw "Unerwartetes GitHub-Repository: $remote"
}

Write-Host ""
Write-Host "=== GIT STATUS ==="

git status --short --untracked-files=all

Write-Host ""
Write-Host "========================================"
Write-Host "PREFLIGHT ERFOLGREICH"
Write-Host "VERSION: $version"
Write-Host "TAG:     $tag"
Write-Host ""
Write-Host "NICHTS COMMITTET"
Write-Host "NICHTS GEPUSHT"
Write-Host "KEIN TAG ERZEUGT"
Write-Host "KEIN RELEASE ERZEUGT"
Write-Host "========================================"

# ------------------------------------------------------------
# Echter Release
# ------------------------------------------------------------

if (-not $Release) {
    Write-Host ""
    Write-Host "Kein -Release angegeben."
    Write-Host "Es wurde nur der Preflight ausgefuehrt."
    exit 0
}

Write-Host ""
Write-Host "========================================"
Write-Host "ECHTER GLINER RELEASE"
Write-Host "========================================"
Write-Host ""

if ($PreflightOnly) {
    throw "-PreflightOnly und -Release duerfen nicht gemeinsam verwendet werden."
}

$branch = (
    git branch --show-current
).Trim()

if ($branch -ne "main") {
    throw "Release ist nur von main erlaubt. Aktuell: $branch"
}

Write-Host "Remote aktualisieren..."

git fetch origin --tags --prune

if ($LASTEXITCODE -ne 0) {
    throw "git fetch fehlgeschlagen."
}

$localHead = (
    git rev-parse HEAD
).Trim()

$remoteHead = (
    git rev-parse origin/main
).Trim()

if ($localHead -ne $remoteHead) {
    throw "STOP: main und origin/main unterscheiden sich."
}

$localTag = @(
    git tag -l $tag
)

if ($localTag.Count -gt 0) {
    throw "STOP: Lokaler Tag existiert bereits: $tag"
}

$remoteTag = @(
    git ls-remote `
        --tags origin `
        "refs/tags/$tag"
)

if ($LASTEXITCODE -ne 0) {
    throw "Remote-Tag-Pruefung fehlgeschlagen."
}

if ($remoteTag.Count -gt 0) {
    throw "STOP: Remote-Tag existiert bereits: $tag"
}

$oldPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$null = gh release view $tag `
    --json tagName `
    2>$null

$releaseViewExit = $LASTEXITCODE

$ErrorActionPreference = $oldPreference

if ($releaseViewExit -eq 0) {
    throw "STOP: GitHub Release existiert bereits: $tag"
}

Write-Host "OK - Release-Ziel ist frei."
Write-Host ""

# Nur die vorgesehenen Dateien committen.
$releaseFiles = @(
    ".github/workflows/gliner.yml",
    ".gitignore",
    "packages/gliner-runtime/current/VERSION",
    "packages/gliner-runtime/current/manifest.json",
    "packages/gliner-runtime/current/GLiNER-Runtime-Windows-x64-CPU.zip.sha256",
    "packages/gliner-runtime/current/GLiNER-Runtime-Windows-x64-CUDA.zip.sha256",
    "scripts/prepare_gliner_source.ps1",
    "scripts/build_gliner_runtime.ps1",
    "scripts/release_gliner_runtime.ps1"
)

Write-Host "=== RELEASE-DATEIEN ==="

foreach ($file in $releaseFiles) {

    $fullPath = Join-Path $repo $file

    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Release-Datei fehlt: $file"
    }

    Write-Host " - $file"
}

Write-Host ""
Write-Host "Stage nur vorgesehene Dateien..."

git add -- $releaseFiles

if ($LASTEXITCODE -ne 0) {
    throw "git add fehlgeschlagen."
}

Write-Host ""
Write-Host "=== STAGED ==="

git diff --cached --name-status

if ($LASTEXITCODE -ne 0) {
    throw "Staging-Pruefung fehlgeschlagen."
}

$stagedFiles = @(
    git diff `
        --cached `
        --name-only
)

$unexpected = @(
    $stagedFiles |
        Where-Object {
            $_ -notin $releaseFiles
        }
)

if ($unexpected.Count -gt 0) {

    git reset

    throw (
        "STOP: Unerwartete Dateien waren staged: " +
        ($unexpected -join ", ")
    )
}

if ($stagedFiles.Count -eq 0) {
    throw "Keine Release-Aenderungen zum Committen vorhanden."
}

Write-Host ""
Write-Host "OK - nur vorgesehene Dateien staged."

$commitMessage = "Prepare GLiNER runtime $version multipart release"

Write-Host ""
Write-Host "Commit:"
Write-Host $commitMessage

git commit `
    -m $commitMessage

if ($LASTEXITCODE -ne 0) {
    throw "Git-Commit fehlgeschlagen."
}

$releaseCommit = (
    git rev-parse HEAD
).Trim()

Write-Host ""
Write-Host "Release-Commit:"
Write-Host $releaseCommit

Write-Host ""
Write-Host "Push main..."

git push origin main

if ($LASTEXITCODE -ne 0) {
    throw "Push von main fehlgeschlagen."
}

$remoteAfterPush = (
    git ls-remote origin `
        "refs/heads/main"
).Split()[0]

if ($remoteAfterPush -ne $releaseCommit) {
    throw "Remote-main zeigt nicht auf den Release-Commit."
}

Write-Host "OK - Release-Commit ist auf origin/main."

Write-Host ""
Write-Host "Tag erzeugen: $tag"

git tag `
    -a $tag `
    -m "GLiNER Runtime $version"

if ($LASTEXITCODE -ne 0) {
    throw "Tag konnte nicht erzeugt werden."
}

git push origin $tag

if ($LASTEXITCODE -ne 0) {
    throw "Tag konnte nicht gepusht werden."
}

Write-Host "OK - Tag gepusht."

# ------------------------------------------------------------
# Release Notes
# ------------------------------------------------------------

$notesPath = Join-Path `
    $repo `
    "temp\gliner-release-notes-$version.md"

$notesDir = Split-Path -Parent $notesPath

New-Item `
    -ItemType Directory `
    -Path $notesDir `
    -Force |
    Out-Null

$notes = @"
# GLiNER Runtime $version

MediaHub GLiNER Runtime fuer Windows x64.

## CPU

- Vollstaendiges CPU-Runtime-Paket
- SHA256-Pruefsumme enthalten

## CUDA

Die CUDA-Runtime wird wegen der GitHub-Assetgroesse als Multipart-Paket bereitgestellt.

Die Dateien muessen in der angegebenen Reihenfolge zusammengesetzt werden:

$(
    (
        $parts |
        ForEach-Object {
            "- ``$($_.file)``"
        }
    ) -join "`r`n"
)

Rekonstruierte Datei:

- ``$($cuda.package)``
- Groesse: $($cuda.size) Bytes
- SHA256: ``$($cuda.sha256)``

Das MediaHub-GLiNER-Plugin uebernimmt spaeter Download,
Pruefung und Zusammensetzen der Parts automatisch.
"@

[System.IO.File]::WriteAllText(
    $notesPath,
    $notes + "`r`n",
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "=== GITHUB RELEASE ERSTELLEN ==="

$releaseAssets = @(
    $cpuPath,
    $cpuHashPath
)

foreach ($entry in $parts) {
    $partPath = Join-Path $releaseRoot $entry.file

    $releaseAssets += $partPath
    $releaseAssets += "$partPath.sha256"
}

$releaseAssets += $manifestPath
$releaseAssets += $versionPath
$releaseAssets += $licensePath

if ($releaseAssets -contains $forbiddenCudaZip) {
    throw "STOP: Grosse CUDA-ZIP befindet sich in Release-Assets."
}

$ghArgs = @(
    "release",
    "create",
    $tag,
    "--title",
    "GLiNER Runtime $version",
    "--notes-file",
    $notesPath,
    "--verify-tag"
)

$ghArgs += $releaseAssets

& gh @ghArgs

if ($LASTEXITCODE -ne 0) {
    throw "GitHub Release konnte nicht erstellt werden."
}

Write-Host ""
Write-Host "=== RELEASE VERIFIZIEREN ==="

gh release view $tag `
    --json tagName,name,isDraft,isPrerelease,url

if ($LASTEXITCODE -ne 0) {
    throw "GitHub Release konnte nach Erstellung nicht gelesen werden."
}

Write-Host ""
Write-Host "=== FINALER GIT STATUS ==="

git status --short --untracked-files=all

Write-Host ""
Write-Host "========================================"
Write-Host "GLINER RELEASE ERFOLGREICH"
Write-Host "VERSION: $version"
Write-Host "TAG:     $tag"
Write-Host "COMMIT:  $releaseCommit"
Write-Host "========================================"