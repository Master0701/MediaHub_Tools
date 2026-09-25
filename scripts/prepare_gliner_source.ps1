param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cpu", "cuda")]
    [string]$Variant,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$Python
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$GlinerVersionFile = Join-Path $repo "tools\gliner-runtime\VERSION"

if (-not (Test-Path -LiteralPath $GlinerVersionFile)) {
    throw "GLiNER VERSION-Datei fehlt: $GlinerVersionFile"
}

$GlinerVersion = (
    Get-Content -LiteralPath $GlinerVersionFile -Raw -Encoding UTF8
).Trim()

if ([string]::IsNullOrWhiteSpace($GlinerVersion)) {
    throw "GLiNER VERSION-Datei ist leer."
}
$TorchVersionCPU = "2.14.0+cpu"
$TorchVersionCUDA = "2.14.0+cu126"

$TorchIndexCPU = "https://download.pytorch.org/whl/cpu"
$TorchIndexCUDA = "https://download.pytorch.org/whl/cu126"

if ([System.IO.Path]::IsPathRooted($Destination)) {
    $destinationPath = [System.IO.Path]::GetFullPath($Destination)
}
else {
    $destinationPath = [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path $Destination)
    )
}

Write-Host "========================================"
Write-Host "MediaHub GLiNER Source Preparation"
Write-Host "========================================"
Write-Host "Variant:     $Variant"
Write-Host "Destination: $destinationPath"
Write-Host "Python:      $Python"
Write-Host ""

if (Test-Path $destinationPath) {
    Write-Host "Entferne vorhandenes Ziel..."
    Remove-Item $destinationPath -Recurse -Force
}

New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null

Write-Host "Pruefe Python 3.12..."

if ([string]::IsNullOrWhiteSpace($Python)) {
    $Python = (& py -3.12 -c "import sys; print(sys.executable)")

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Python)) {
        throw "Python 3.12 wurde nicht gefunden. Installiere es mit: py install 3.12"
    }

    $Python = $Python.Trim()
}

if (-not (Test-Path -LiteralPath $Python)) {
    throw "Python-Interpreter wurde nicht gefunden: $Python"
}

$pythonInfo = (& $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}|{sys.implementation.cache_tag}|{sys.executable}')")

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pythonInfo)) {
    throw "Python konnte nicht korrekt gestartet werden."
}

$pythonInfo = $pythonInfo.Trim()
$pythonParts = $pythonInfo.Split("|")

if ($pythonParts.Count -ne 3) {
    throw "Python-Versionspruefung lieferte ein unerwartetes Ergebnis: $pythonInfo"
}

$pythonVersion = $pythonParts[0]
$pythonCacheTag = $pythonParts[1]
$pythonExecutable = $pythonParts[2]

if ($pythonVersion -ne "3.12" -or $pythonCacheTag -ne "cpython-312") {
    throw "Falsches Python fuer GLiNER: $pythonVersion / $pythonCacheTag. Erforderlich ist CPython 3.12."
}

$Python = $pythonExecutable

Write-Host "OK - CPython 3.12 erkannt."
Write-Host "Interpreter: $Python"
Write-Host "ABI:         $pythonCacheTag"

Write-Host ""
Write-Host "Aktualisiere pip..."
& $Python -m pip install --upgrade pip

if ($LASTEXITCODE -ne 0) {
    throw "pip konnte nicht aktualisiert werden."
}

if ($Variant -eq "cpu") {
    $torchVersion = $TorchVersionCPU
    $torchIndex = $TorchIndexCPU
}
else {
    $torchVersion = $TorchVersionCUDA
    $torchIndex = $TorchIndexCUDA
}

Write-Host ""
Write-Host "Installiere Torch..."
Write-Host "Version: $torchVersion"
Write-Host "Index:   $torchIndex"

& $Python -m pip install `
    --target $destinationPath `
    --index-url $torchIndex `
    "torch==$torchVersion"

if ($LASTEXITCODE -ne 0) {
    throw "Torch-Installation fehlgeschlagen."
}

Write-Host ""
Write-Host "Installiere GLiNER..."
Write-Host "Version: $GlinerVersion"

& $Python -m pip install `
    --target $destinationPath `
    --no-deps `
    "gliner==$GlinerVersion"

if ($LASTEXITCODE -ne 0) {
    throw "GLiNER-Installation fehlgeschlagen."
}

Write-Host ""
Write-Host "Installiere GLiNER-Abhaengigkeiten..."

& $Python -m pip install `
    --target $destinationPath `
    --no-deps `
    "transformers==5.16.1" `
    "huggingface_hub==1.32.0" `
    "numpy==2.5.3" `
    "packaging==26.3" `
    "safetensors==0.8.0" `
    "tqdm==4.70.1" `
    "sentencepiece==0.2.2" `
    "pyyaml==6.0.3" `
    "regex==2026.9.10" `
    "tokenizers==0.23.2" `
    "typer==0.27.2" `
    "click==8.5.0" `
    "hf-xet==1.6.0" `
    "httpx==0.28.1" `
    "httpcore==1.0.9" `
    "idna==3.20" `
    "h11==0.16.0" `
    "anyio==4.15.1" `
    "certifi==2026.7.22" `
    "colorama==0.4.6" `
    "shellingham==1.5.4" `
    "rich==15.0.0" `
    "annotated-doc==0.0.5" `
    "markdown-it-py==4.2.0" `
    "pygments==2.21.0" `
    "mdurl==0.1.2"

if ($LASTEXITCODE -ne 0) {
    throw "GLiNER-Abhaengigkeitsinstallation fehlgeschlagen."
}

Write-Host ""
Write-Host "Pruefe Kernpakete..."

$required = @(
    "gliner",
    "torch",
    "transformers",
    "tokenizers",
    "safetensors",
    "sentencepiece",
    "numpy"
)

foreach ($package in $required) {

    $found = Get-ChildItem `
        $destinationPath `
        -Directory `
        -Filter "$package*" `
        -ErrorAction SilentlyContinue

    if (-not $found) {
        throw "Pflichtpaket fehlt im Source: $package"
    }

    Write-Host "OK: $package"
}

Write-Host ""
Write-Host "Distributionen:"

$distInfo = @(
    Get-ChildItem `
        $destinationPath `
        -Directory `
        -Filter "*.dist-info" `
        -ErrorAction SilentlyContinue
)

$distInfo |
    Sort-Object Name |
    Select-Object Name |
    Format-Table -AutoSize

Write-Host "Anzahl: $($distInfo.Count)"

Write-Host ""
Write-Host "========================================"
Write-Host "SOURCE ERFOLGREICH ERZEUGT"
Write-Host "========================================"
Write-Host "Variant: $Variant"
Write-Host "Source:  $destinationPath"
Write-Host "========================================"


