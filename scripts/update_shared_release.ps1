param(
    [string]$ReleaseTag = "mediahub-tools"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$tesseractManifestPath = Join-Path $Root "packages\tesseract\current\manifest.json"
$glinerManifestPath    = Join-Path $Root "packages\gliner-runtime\current\manifest.json"
$smolvlmManifestPath   = Join-Path $Root "packages\smolvlm2-model\current\manifest.json"

foreach ($manifestPath in @(
    $tesseractManifestPath,
    $glinerManifestPath,
    $smolvlmManifestPath
)) {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Manifest fehlt: $manifestPath"
    }
}

$tesseractManifest = Get-Content `
    -LiteralPath $tesseractManifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

$glinerManifest = Get-Content `
    -LiteralPath $glinerManifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

$smolvlmManifest = Get-Content `
    -LiteralPath $smolvlmManifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

$tesseractVersion = [string]$tesseractManifest.version
$runtimeVersion   = [string]$glinerManifest.version
$glinerVersion    = [string]$glinerManifest.gliner_version
$smolvlmVersion   = [string]$smolvlmManifest.version

foreach ($versionInfo in @(
    @{ Name = "Tesseract"; Value = $tesseractVersion },
    @{ Name = "GLiNER Runtime"; Value = $runtimeVersion },
    @{ Name = "GLiNER"; Value = $glinerVersion },
    @{ Name = "SmolVLM2"; Value = $smolvlmVersion }
)) {
    if ([string]::IsNullOrWhiteSpace($versionInfo.Value)) {
        throw "$($versionInfo.Name)-Version fehlt im Manifest."
    }
}

Write-Host ""
Write-Host "=== GEMEINSAMEN RELEASE-TEXT AKTUALISIEREN ==="
Write-Host "Release:            $ReleaseTag"
Write-Host "Tesseract:          $tesseractVersion"
Write-Host "GLiNER Runtime:     $runtimeVersion"
Write-Host "GLiNER:             $glinerVersion"
Write-Host "SmolVLM2:           $smolvlmVersion"
Write-Host ""

$releaseBodyPath = Join-Path $env:TEMP "mediahub-tools-release.md"

$releaseBody = @"
# MediaHub Tools

Gemeinsames Release der von MediaHub verwendeten Zusatztools.

## Tesseract OCR

Version: $tesseractVersion

- Tesseract-Projekt.zip
- SHA256-Pruefsumme
- eigenes Tesseract-Manifest

## GLiNER Runtime

Runtime-Version: $runtimeVersion
GLiNER-Version: $glinerVersion

- Windows x64 CPU Runtime
- Windows x64 CUDA Runtime als Multipart-Paket
- Linux ARM64 / Raspberry Pi CPU Runtime
- gemeinsames Modell gliner_multi-v2.1
- Modellformat: Safetensors
- SHA256-Pruefsummen
- eigenes GLiNER-Manifest

## SmolVLM2

Version: $smolvlmVersion

- SmolVLM2-500M-Video-Instruct
- Windows Compute Node
- Raspberry Pi / Linux ARM64
- gemeinsames Modellpaket fuer beide Plattformen
- SHA256-Pruefsumme
- eigenes Modell-Manifest

## Lizenzen

Die zentrale THIRD_PARTY_LICENSES.md enthaelt die Hinweise
zu den im MediaHub-Tools-Repository verwalteten Drittanbieter-Komponenten.

Dieses gemeinsame Release wird von den einzelnen Tool-
Updateprozessen aktualisiert. Ein Tool darf dabei die
Assets anderer Tools nicht entfernen.
"@

try {
    Set-Content `
        -LiteralPath $releaseBodyPath `
        -Value $releaseBody `
        -Encoding UTF8 `
        -NoNewline

    & gh release edit $ReleaseTag `
        --title "MediaHub Tools" `
        --notes-file $releaseBodyPath

    if ($LASTEXITCODE -ne 0) {
        throw "Gemeinsamer Release-Text konnte nicht aktualisiert werden."
    }
}
finally {
    Remove-Item `
        -LiteralPath $releaseBodyPath `
        -Force `
        -ErrorAction SilentlyContinue
}

Write-Host "OK - gemeinsamer Release-Text aktualisiert."