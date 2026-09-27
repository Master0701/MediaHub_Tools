param(
    [switch]$SkipBuild,
    [switch]$PreflightOnly
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$buildScript = Join-Path $PSScriptRoot "build_smolvlm2_model.ps1"

$releaseDir = Join-Path $repo "release\smolvlm2-model"

$packageName = "SmolVLM2-500M-Video-Instruct-v0.1.0.zip"
$packagePath = Join-Path $releaseDir $packageName
$shaPath = "$packagePath.sha256"

$manifestPath = Join-Path `
    $releaseDir `
    "smolvlm2-model-manifest.json"

$releaseTag = "mediahub-tools"

$expectedModel = "HuggingFaceTB/SmolVLM2-500M-Video-Instruct"
$expectedRevision = "7b375e1b73b11138ff12fe22c8f2822d8fe03467"
$expectedVersion = "0.1.0"

Write-Host "========================================"
Write-Host "SMOLVLM2 MODEL RELEASE"
Write-Host "========================================"
Write-Host ""

# ------------------------------------------------------------
# Hilfsfunktionen
# ------------------------------------------------------------

function Require-Command {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "STOP: Benoetigter Befehl fehlt: $Name"
    }
}

function Require-File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "STOP: Pflichtdatei fehlt: $Path"
    }
}

# ------------------------------------------------------------
# Voraussetzungen
# ------------------------------------------------------------

Require-Command "git"
Require-Command "gh"

Require-File $buildScript
Require-File (Join-Path $repo "THIRD_PARTY_LICENSES.md")
Require-File (Join-Path $repo "tools\smolvlm2-model\THIRD_PARTY_NOTICE.md")
Require-File (Join-Path $repo "tools\smolvlm2-model\tool.json")
Require-File (Join-Path $repo "packages\smolvlm2-model\current\manifest.json")

Write-Host "OK: Grundvoraussetzungen"

# ------------------------------------------------------------
# Git Repository
# ------------------------------------------------------------

$inside = git rev-parse --is-inside-work-tree

if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
    throw "STOP: Kein Git-Repository."
}

$branch = (git branch --show-current).Trim()

if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "STOP: Kein aktiver Git-Branch."
}

Write-Host "Git-Branch: $branch"

# ------------------------------------------------------------
# GitHub CLI
# ------------------------------------------------------------

gh auth status

if ($LASTEXITCODE -ne 0) {
    throw "STOP: GitHub CLI ist nicht angemeldet."
}

Write-Host "OK: GitHub CLI"

# ------------------------------------------------------------
# Lizenz-/Metadatenprüfung
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== LIZENZ / METADATEN ==="

$thirdPartyText = Get-Content `
    (Join-Path $repo "THIRD_PARTY_LICENSES.md") `
    -Raw `
    -Encoding UTF8

if ($thirdPartyText -notmatch [regex]::Escape($expectedModel)) {
    throw "STOP: SmolVLM2 fehlt in THIRD_PARTY_LICENSES.md."
}

if ($thirdPartyText -notmatch "Apache-2\.0") {
    throw "STOP: Apache-2.0-Hinweis fehlt."
}

$toolJson = Get-Content `
    (Join-Path $repo "tools\smolvlm2-model\tool.json") `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

if ($toolJson.id -ne "smolvlm2-model") {
    throw "STOP: Falsche Tool-ID."
}

if ($toolJson.package_version -ne $expectedVersion) {
    throw "STOP: Falsche Tool-Version."
}

if ($toolJson.model_revision -ne $expectedRevision) {
    throw "STOP: Falsche Modellrevision."
}

if ($toolJson.license -ne "Apache-2.0") {
    throw "STOP: Falsche Modelllizenz."
}

Write-Host "OK: Lizenz und Tool-Metadaten"

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

if (-not $SkipBuild) {

    Write-Host ""
    Write-Host "=== BUILD ==="

    & $buildScript

    if ($LASTEXITCODE -ne 0) {
        throw "STOP: SmolVLM2-Build fehlgeschlagen."
    }
}
else {
    Write-Host ""
    Write-Host "Build uebersprungen (-SkipBuild)."
}

Require-File $packagePath
Require-File $shaPath
Require-File $manifestPath

# ------------------------------------------------------------
# Release Manifest
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== RELEASE-MANIFEST ==="

$manifest = Get-Content `
    $manifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

if ($manifest.tool -ne "smolvlm2-model") {
    throw "STOP: Falsches Tool im Release-Manifest."
}

if ($manifest.version -ne $expectedVersion) {
    throw "STOP: Falsche Version im Release-Manifest."
}

if ($manifest.model -ne $expectedModel) {
    throw "STOP: Falsches Modell im Release-Manifest."
}

if ($manifest.revision -ne $expectedRevision) {
    throw "STOP: Falsche Revision im Release-Manifest."
}

if ($manifest.license -ne "Apache-2.0") {
    throw "STOP: Falsche Lizenz im Release-Manifest."
}

if ($manifest.multipart -ne $false) {
    throw "STOP: SmolVLM2 muss aktuell Single-ZIP sein."
}

if ($manifest.package -ne $packageName) {
    throw "STOP: Paketname stimmt nicht."
}

Write-Host "OK: Release-Manifest"

# ------------------------------------------------------------
# SHA256
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== SHA256 ==="

$actualHash = (
    Get-FileHash `
        -LiteralPath $packagePath `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$storedHash = (
    (
        Get-Content `
            -LiteralPath $shaPath `
            -Raw
    ).Trim() -split '\s+'
)[0].ToLowerInvariant()

if ($actualHash -ne $storedHash) {
    throw "STOP: ZIP-SHA256 stimmt nicht."
}

if ($manifest.sha256.ToLowerInvariant() -ne $actualHash) {
    throw "STOP: Manifest-SHA256 stimmt nicht."
}

$packageFile = Get-Item -LiteralPath $packagePath

if ([int64]$manifest.size -ne [int64]$packageFile.Length) {
    throw "STOP: Paketgroesse stimmt nicht mit Manifest ueberein."
}

Write-Host "OK: SHA256 $actualHash"
Write-Host "Groesse: $($packageFile.Length) Byte"

# ------------------------------------------------------------
# ZIP-Inhalt
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== ZIP-INHALT ==="

Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [System.IO.Compression.ZipFile]::OpenRead(
    (Resolve-Path $packagePath)
)

try {

    $entries = @(
        $archive.Entries |
        Where-Object {
            -not $_.FullName.EndsWith("/")
        }
    )

    $requiredModelFiles = @(
        "added_tokens.json",
        "chat_template.json",
        "config.json",
        "generation_config.json",
        "model.safetensors",
        "preprocessor_config.json",
        "processor_config.json",
        "special_tokens_map.json",
        "tokenizer.json",
        "tokenizer_config.json"
    )

    foreach ($name in $requiredModelFiles) {

        $matches = @(
            $entries |
            Where-Object {
                [System.IO.Path]::GetFileName(
                    $_.FullName
                ) -eq $name
            }
        )

        if ($matches.Count -ne 1) {
            throw "STOP: ZIP-Datei $name wurde $($matches.Count)x gefunden."
        }

        if ($matches[0].Length -le 0) {
            throw "STOP: ZIP-Datei $name ist leer."
        }
    }

    foreach ($requiredMeta in @(
        "manifest.json",
        "VERSION",
        "THIRD_PARTY_NOTICE.md",
        "THIRD_PARTY_LICENSES.md"
    )) {

        $matches = @(
            $entries |
            Where-Object {
                [System.IO.Path]::GetFileName(
                    $_.FullName
                ) -eq $requiredMeta
            }
        )

        if ($matches.Count -ne 1) {
            throw "STOP: $requiredMeta fehlt oder ist mehrfach vorhanden."
        }
    }

    $unsafe = @(
        $entries |
        Where-Object {
            $_.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or
            $_.FullName.StartsWith("/") -or
            $_.FullName.StartsWith("\")
        }
    )

    if ($unsafe.Count -ne 0) {
        throw "STOP: Unsichere ZIP-Pfade gefunden."
    }
}
finally {
    $archive.Dispose()
}

Write-Host "OK: ZIP-Inhalt"

# ------------------------------------------------------------
# Vorhandenes GitHub Release
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== GITHUB RELEASE ==="

gh release view $releaseTag --json tagName,name

if ($LASTEXITCODE -ne 0) {
    throw "STOP: GitHub Release '$releaseTag' wurde nicht gefunden."
}

Write-Host "OK: gemeinsames MediaHub-Tools-Release vorhanden"

# ------------------------------------------------------------
# Git Status anzeigen
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== GIT STATUS ==="

git status --short

Write-Host ""
Write-Host "HINWEIS:"
Write-Host "scripts/release_tesseract.ps1 wird von diesem Assistenten"
Write-Host "weder gestaged noch veraendert."

# ------------------------------------------------------------
# Nur Preflight?
# ------------------------------------------------------------

if ($PreflightOnly) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host "PREFLIGHT ERFOLGREICH"
    Write-Host "NICHTS COMMITTED"
    Write-Host "NICHTS HOCHGELADEN"
    Write-Host "========================================"

    exit 0
}

# ------------------------------------------------------------
# Explizite Freigabe
# ------------------------------------------------------------

Write-Host ""
Write-Host "Alle Preflight-Pruefungen sind erfolgreich."
Write-Host ""
Write-Host "Der naechste Schritt wuerde:"
Write-Host "  - SmolVLM2-Dateien stagen"
Write-Host "  - committen"
Write-Host "  - pushen"
Write-Host "  - Release-Assets hochladen/ersetzen"
Write-Host ""

$confirmation = Read-Host `
    "Zum Veröffentlichen exakt RELEASE eingeben"

if ($confirmation -cne "RELEASE") {
    throw "Abgebrochen - keine Veroeffentlichung."
}

# ------------------------------------------------------------
# Nur definierte Dateien stagen
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== GIT STAGING ==="

$stagePaths = @(
    "README.md",
    "THIRD_PARTY_LICENSES.md",
    "packages/smolvlm2-model",
    "scripts/build_smolvlm2_model.ps1",
    "scripts/release_smolvlm2_model.ps1",
    "tools/smolvlm2-model"
)

foreach ($path in $stagePaths) {
    git add -- $path

    if ($LASTEXITCODE -ne 0) {
        throw "STOP: git add fehlgeschlagen: $path"
    }
}

$staged = git diff --cached --name-only

Write-Host ""
Write-Host "Gestaged:"
$staged

if (
    $staged -contains "scripts/release_tesseract.ps1"
) {
    throw "STOP: release_tesseract.ps1 wurde unerwartet gestaged."
}

$allowedPrefixes = @(
    "README.md",
    "THIRD_PARTY_LICENSES.md",
    "packages/smolvlm2-model/",
    "scripts/build_smolvlm2_model.ps1",
    "scripts/release_smolvlm2_model.ps1",
    "tools/smolvlm2-model/"
)

foreach ($file in $staged) {

    $allowed = $false

    foreach ($prefix in $allowedPrefixes) {

        if (
            $file -eq $prefix -or
            $file.StartsWith($prefix)
        ) {
            $allowed = $true
            break
        }
    }

    if (-not $allowed) {
        throw "STOP: Unerwartete gestagete Datei: $file"
    }
}

if (@($staged).Count -eq 0) {
    throw "STOP: Keine SmolVLM2-Aenderungen zum Committen."
}

# ------------------------------------------------------------
# Commit + Push
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== COMMIT ==="

git commit -m "Add SmolVLM2 model package"

if ($LASTEXITCODE -ne 0) {
    throw "STOP: Git-Commit fehlgeschlagen."
}

Write-Host ""
Write-Host "=== PUSH ==="

git push origin $branch

if ($LASTEXITCODE -ne 0) {
    throw "STOP: Git-Push fehlgeschlagen."
}

# ------------------------------------------------------------
# GitHub Assets
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== RELEASE ASSETS ==="

$assets = @(
    $packagePath,
    $shaPath,
    $manifestPath
)

foreach ($asset in $assets) {

    Require-File $asset

    Write-Host "Upload:"
    Write-Host $asset

    gh release upload `
        $releaseTag `
        $asset `
        --clobber

    if ($LASTEXITCODE -ne 0) {
        throw "STOP: GitHub-Upload fehlgeschlagen: $asset"
    }
}

# ------------------------------------------------------------
# Abschlusskontrolle
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== ABSCHLUSSKONTROLLE ==="

gh release view `
    $releaseTag `
    --json tagName,name,assets

if ($LASTEXITCODE -ne 0) {
    throw "STOP: Release-Abschlusskontrolle fehlgeschlagen."
}

Write-Host ""
Write-Host "========================================"
Write-Host "SMOLVLM2 RELEASE ERFOLGREICH"
Write-Host "========================================"
