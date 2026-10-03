param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Current = Join-Path $Root "packages\tesseract\current"

$Zip      = Join-Path $Current "Tesseract-Projekt.zip"
$Sha      = Join-Path $Current "Tesseract-Projekt.zip.sha256"
$Manifest = Join-Path $Current "tesseract-manifest.json"
$Version  = Join-Path $Current "VERSION"
$Licenses = Join-Path $Root "THIRD_PARTY_LICENSES.md"

$ReleaseTag = "mediahub-tools"

Write-Host ""
Write-Host "========================================"
Write-Host "TESSERACT SHARED RELEASE PREFLIGHT"
Write-Host "========================================"
Write-Host ""

$Required = @(
    $Zip,
    $Sha,
    $Manifest,
    $Version,
    $Licenses
)

foreach ($File in $Required) {

    if (-not (Test-Path -LiteralPath $File)) {
        throw "Pflichtdatei fehlt: $File"
    }

    Write-Host "OK - $(Split-Path $File -Leaf)"
}

$TesseractVersion = (
    Get-Content `
        -LiteralPath $Version `
        -Raw `
        -Encoding UTF8
).Trim()

if ([string]::IsNullOrWhiteSpace($TesseractVersion)) {
    throw "Tesseract VERSION ist leer."
}

Write-Host ""
Write-Host "Version: $TesseractVersion"
Write-Host "Release: $ReleaseTag"
Write-Host ""

# ------------------------------------------------------------
# SHA256 kontrollieren
# ------------------------------------------------------------

Write-Host "=== SHA256 PRUEFEN ==="

$ActualHash = (
    Get-FileHash `
        -LiteralPath $Zip `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$ShaText = (
    Get-Content `
        -LiteralPath $Sha `
        -Raw `
        -Encoding ASCII
).Trim()

$ExpectedHash = ($ShaText -split '\s+')[0].ToLowerInvariant()

if ($ActualHash -ne $ExpectedHash) {
    throw "SHA256 stimmt NICHT mit Tesseract-Projekt.zip ueberein."
}

Write-Host "OK - SHA256"
Write-Host $ActualHash
Write-Host ""

# ------------------------------------------------------------
# Manifest kontrollieren
# ------------------------------------------------------------

Write-Host "=== MANIFEST PRUEFEN ==="

$ManifestData = Get-Content `
    -LiteralPath $Manifest `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

if ($ManifestData.tool -ne "tesseract") {
    throw "Manifest gehoert nicht zu Tesseract."
}

if ($ManifestData.release_tag -ne $ReleaseTag) {
    throw "Manifest verweist nicht auf mediahub-tools."
}

if ($ManifestData.package -ne "Tesseract-Projekt.zip") {
    throw "Falscher Paketname im Manifest."
}

if ($ManifestData.sha256.ToLowerInvariant() -ne $ActualHash) {
    throw "Manifest-SHA256 stimmt nicht."
}

Write-Host "OK - Manifest"
Write-Host ""

# ------------------------------------------------------------
# GitHub CLI / gemeinsamer Release
# ------------------------------------------------------------

Write-Host "=== GITHUB PRUEFEN ==="

& gh auth status

if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI ist nicht angemeldet."
}

& gh release view $ReleaseTag *> $null

if ($LASTEXITCODE -ne 0) {
    throw "Gemeinsamer GitHub Release '$ReleaseTag' existiert nicht."
}

Write-Host "OK - gemeinsamer Release existiert."
Write-Host ""

Write-Host "Ziel:"
Write-Host "  $ReleaseTag"
Write-Host ""
Write-Host "Assets:"
Write-Host "  Tesseract-Projekt.zip"
Write-Host "  Tesseract-Projekt.zip.sha256"
Write-Host "  tesseract-manifest.json"
Write-Host "  THIRD_PARTY_LICENSES.md"
Write-Host ""

if (-not $Release) {

    Write-Host "========================================"
    Write-Host "PREFLIGHT ERFOLGREICH"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "NICHTS HOCHGELADEN"
    Write-Host "KEIN TAG ERZEUGT"
    Write-Host "KEIN RELEASE ERZEUGT"
    Write-Host ""

    exit 0
}

# ------------------------------------------------------------
# Bestehenden gemeinsamen Release aktualisieren
# ------------------------------------------------------------

Write-Host "========================================"
Write-Host "TESSERACT RELEASE STARTEN"
Write-Host "========================================"
Write-Host ""

& gh release upload `
    $ReleaseTag `
    $Zip `
    $Sha `
    $Manifest `
    $Licenses `
    --clobber

if ($LASTEXITCODE -ne 0) {
    throw "Upload der Tesseract-Assets fehlgeschlagen."
}

Write-Host ""
Write-Host "=== GEMEINSAMEN RELEASE-TEXT AKTUALISIEREN ==="

$SharedReleaseScript = Join-Path $PSScriptRoot "update_shared_release.ps1"

if (-not (Test-Path -LiteralPath $SharedReleaseScript)) {
    throw "Zentrales Shared-Release-Script fehlt: $SharedReleaseScript"
}

& $SharedReleaseScript -ReleaseTag $ReleaseTag

if ($LASTEXITCODE -ne 0) {
    throw "Zentrales Shared-Release-Script ist fehlgeschlagen."
}

Write-Host ""
Write-Host "=== RELEASE-ASSETS PRUEFEN ==="

$Assets = @(
    gh release view `
        $ReleaseTag `
        --json assets `
        --jq '.assets[].name'
)

$RequiredAssets = @(
    "Tesseract-Projekt.zip",
    "Tesseract-Projekt.zip.sha256",
    "tesseract-manifest.json",
    "THIRD_PARTY_LICENSES.md"
)

foreach ($Asset in $RequiredAssets) {

    if ($Assets -notcontains $Asset) {
        throw "Release-Asset fehlt nach Upload: $Asset"
    }

    Write-Host "OK - $Asset"
}

Write-Host ""
Write-Host "========================================"
Write-Host "TESSERACT RELEASE ERFOLGREICH"
Write-Host "========================================"
Write-Host ""
Write-Host "Version: $TesseractVersion"
Write-Host "Release: $ReleaseTag"
Write-Host ""
Write-Host "KEIN neuer Tag erzeugt."
Write-Host "KEIN separater Tesseract-Release erzeugt."
Write-Host ""

exit 0
