param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cpu", "cuda")]
    [string]$Variant,

    [Parameter(Mandatory = $true)]
    [string]$Source
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo "work\gliner-runtime\$Variant"
$release = Join-Path $repo "release\gliner-runtime"

if (-not (Test-Path $Source)) {
    throw "Quell-Runtime fehlt: $Source"
}

Write-Host "=== GLINER RUNTIME BUILD ==="
Write-Host "Variante: $Variant"
Write-Host "Quelle:   $Source"
Write-Host "Work:     $work"
Write-Host ""


# ------------------------------------------------------------
# Doppelte Python-Distributionen pruefen
# ------------------------------------------------------------

Write-Host "Pruefe Quell-Runtime auf doppelte Python-Distributionen..."

$distributionEntries = @(
    Get-ChildItem `
        $Source `
        -Directory `
        -Force `
        -ErrorAction Stop |
    Where-Object {
        $_.Name -like "*.dist-info"
    } |
    ForEach-Object {

        $metadata = Join-Path $_.FullName "METADATA"

        if (Test-Path $metadata) {

            $metadataLines = Get-Content `
                $metadata `
                -Encoding UTF8 `
                -ErrorAction Stop

            $nameLine = $metadataLines |
                Where-Object {
                    $_ -like "Name: *"
                } |
                Select-Object -First 1

            $versionLine = $metadataLines |
                Where-Object {
                    $_ -like "Version: *"
                } |
                Select-Object -First 1

            if ($nameLine -and $versionLine) {

                [PSCustomObject]@{
                    Name = (
                        $nameLine -replace '^Name:\s*', ''
                    ).Trim()

                    Version = (
                        $versionLine -replace '^Version:\s*', ''
                    ).Trim()

                    Directory = $_.Name
                }
            }
        }
    }
)

$duplicateDistributions = @(
    $distributionEntries |
    Group-Object {
        $_.Name.ToLowerInvariant().Replace("_", "-")
    } |
    Where-Object {
        $_.Count -gt 1
    }
)

if ($duplicateDistributions.Count -gt 0) {

    Write-Host ""
    Write-Host "Doppelte Python-Distributionen gefunden:"
    Write-Host ""

    foreach ($group in $duplicateDistributions) {

        Write-Host "DUPLIKAT: $($group.Group[0].Name)"

        $group.Group |
            Sort-Object Version |
            Format-Table `
                Name,
                Version,
                Directory `
                -AutoSize

        Write-Host ""
    }

    # Bekannter Sonderfall:
    #
    # Die bestehende CUDA-Quell-Runtime enthaelt alte dist-info-
    # Metadaten fuer filelock und fsspec. Die eigentlichen Module
    # stammen bereits aus den neueren Versionen.
    #
    # Ausschliesslich diese exakt bekannte Kombination darf
    # weiterverarbeitet werden. Die Quell-Runtime selbst wird
    # niemals veraendert.

    $allowedDuplicateDirectories = @(
        "filelock-3.32.3.dist-info",
        "filelock-4.0.1.dist-info",
        "fsspec-2026.7.0.dist-info",
        "fsspec-2026.9.0.dist-info"
    )

    $duplicateDirectories = @(
        $duplicateDistributions |
        ForEach-Object {
            $_.Group
        } |
        ForEach-Object {
            $_.Directory
        } |
        Sort-Object
    )

    $expectedDuplicateDirectories = @(
        $allowedDuplicateDirectories |
        Sort-Object
    )

    $knownCudaDuplicateSet = (
        $duplicateDistributions.Count -eq 2 -and
        $duplicateDirectories.Count -eq 4 -and
        (
            Compare-Object `
                $expectedDuplicateDirectories `
                $duplicateDirectories
        ).Count -eq 0
    )

    switch ($knownCudaDuplicateSet) {
        $false {
            throw (
                "Quell-Runtime enthaelt unbekannte doppelte " +
                "dist-info-Metadaten. Build wird aus " +
                "Sicherheitsgruenden abgebrochen."
            )
        }
    }

    Write-Host "OK - ausschliesslich bekannte CUDA-Altmetadaten gefunden."
    Write-Host "Quell-Runtime bleibt unveraendert."
    Write-Host ""
}
Write-Host (
    "OK - {0} Distributionseintraege geprueft." -f `
    $distributionEntries.Count
)
Write-Host ""
if (Test-Path $work) {
    Remove-Item $work -Recurse -Force
}

New-Item $work -ItemType Directory -Force | Out-Null
New-Item $release -ItemType Directory -Force | Out-Null

Write-Host "Kopiere Runtime..."

Copy-Item `
    (Join-Path $Source "*") `
    $work `
    -Recurse `
    -Force

Write-Host "OK"
Write-Host ""
Write-Host ""
# Python-Bytecode und Caches
# ------------------------------------------------------------

Write-Host "Entferne Python-Bytecode und Caches..."

Get-ChildItem `
    $work `
    -Directory `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue |
Where-Object {
    $_.Name -eq "__pycache__" -or
    $_.Name -eq ".pytest_cache"
} |
Sort-Object FullName -Descending |
ForEach-Object {
    Remove-Item `
        $_.FullName `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}

Get-ChildItem `
    $work `
    -File `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue |
Where-Object {
    $_.Extension -eq ".pyc" -or
    $_.Extension -eq ".pyo"
} |
Remove-Item `
    -Force `
    -ErrorAction SilentlyContinue

Write-Host "OK"
Write-Host ""

# ------------------------------------------------------------
# Unnoetige Test-/Benchmark-Verzeichnisse
#
# WICHTIG:
# Verzeichnisse innerhalb *.dist-info werden NICHT geloescht.
# Damit bleiben insbesondere Lizenz-/Metadaten erhalten.
# ------------------------------------------------------------

Write-Host "Entferne unnoetige Test-/Benchmark-Verzeichnisse..."

$removeDirectoryNames = @(
    "tests",
    "test",
    "testing",
    "benchmarks",
    "benchmark"
)

$candidates = @(
    Get-ChildItem `
        $work `
        -Directory `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $removeDirectoryNames -contains $_.Name.ToLowerInvariant()
    }
)

$removedCount = 0
$protectedCount = 0

foreach ($directory in (
    $candidates |
    Sort-Object FullName -Descending
)) {

    $relative = $directory.FullName.Substring(
        $work.Length
    ).TrimStart("\", "/")

    $parts = $relative -split '[\\/]'

    $insideDistInfo = @(
        $parts |
        Where-Object {
            $_ -like "*.dist-info"
        }
    ).Count -gt 0

    # PyTorch verwendet selbst Verzeichnisse mit Namen wie
    # testing und benchmark zur Laufzeit. Deshalb darf die
    # generische Test-Verzeichnis-Bereinigung innerhalb des
    # kompletten Top-Level-Pakets torch nichts entfernen.
    $insideTorch = (
        $parts.Count -gt 0 -and
        $parts[0] -eq "torch"
    )

    if ($insideDistInfo -or $insideTorch) {

        $reason = if ($insideDistInfo) {
            "dist-info"
        }
        else {
            "torch-runtime"
        }

        Write-Host "GESCHUETZT ($reason):"
        Write-Host "  $relative"

        $protectedCount++
        continue
    }

    Write-Host "ENTFERNE:"
    Write-Host "  $relative"

    Remove-Item `
        $directory.FullName `
        -Recurse `
        -Force `
        -ErrorAction Stop

    $removedCount++
}

Write-Host ""
Write-Host "Entfernte Verzeichnisse: $removedCount"
Write-Host "Geschuetzte dist-info-Verzeichnisse: $protectedCount"
Write-Host ""

# ------------------------------------------------------------
# Finale Cache-Kontrolle
# ------------------------------------------------------------

Write-Host "Finale Bytecode-/Cache-Kontrolle..."

$cacheRemainders = @(
    Get-ChildItem `
        $work `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "__pycache__" -or
        $_.Name -eq ".pytest_cache" -or
        $_.Extension -eq ".pyc" -or
        $_.Extension -eq ".pyo"
    }
)

if ($cacheRemainders.Count -ne 0) {
    throw (
        "Bereinigung unvollstaendig: " +
        "$($cacheRemainders.Count) Cache-/Bytecode-Reste gefunden."
    )
}

Write-Host "OK"
Write-Host ""

# ------------------------------------------------------------
# Pflichtpakete
# ------------------------------------------------------------

Write-Host "Pruefe Pflichtpakete..."

$requiredPackages = @(
    "gliner",
    "torch",
    "transformers",
    "huggingface_hub",
    "tokenizers",
    "safetensors",
    "sentencepiece"
)

foreach ($package in $requiredPackages) {

    $packagePath = Join-Path $work $package

    if (-not (Test-Path $packagePath)) {
        throw "Pflichtpaket fehlt nach Bereinigung: $package"
    }

    Write-Host "OK - $package"
}

Write-Host ""

# ------------------------------------------------------------
# Release-Metadaten
# ------------------------------------------------------------

$torchVersion = if ($Variant -eq "cuda") {
    "2.14.0+cu126"
}
else {
    "2.14.0+cpu"
}

$acceleration = if ($Variant -eq "cuda") {
    "nvidia-cuda"
}
else {
    "cpu"
}

# Altes Manifest darf die Groessenberechnung nicht beeinflussen.

$manifestPath = Join-Path `
    $work `
    "mediahub-runtime.json"

if (Test-Path $manifestPath) {
    Remove-Item $manifestPath -Force
}

$size = (
    Get-ChildItem `
        $work `
        -File `
        -Recurse `
        -Force |
    Measure-Object Length -Sum
).Sum

$manifest = [ordered]@{
    schema_version = 1
    tool = "gliner-runtime"
    variant = $Variant
    platform = "windows"
    architecture = "x64"
    gliner_version = "0.2.29"
    torch_version = $torchVersion
    acceleration = $acceleration
    source_project = "urchade/GLiNER"
    source_model = "urchade/gliner_multi-v2.1"
    build_time_utc = [DateTime]::UtcNow.ToString("o")
    size_bytes = $size
}

$manifest |
ConvertTo-Json -Depth 10 |
Set-Content `
    $manifestPath `
    -Encoding UTF8

Write-Host (
    "Finale Runtime: {0:N3} GB ({1:N1} MB)" -f `
    ($size / 1GB),
    ($size / 1MB)
)

Write-Host ""
Write-Host "Manifest:"
Get-Content $manifestPath -Encoding UTF8

Write-Host ""
Write-Host "========================================"
Write-Host "BUILD-STAGING FERTIG"
Write-Host "VARIANTE: $($Variant.ToUpper())"

# ------------------------------------------------------------
# Release-Paket erzeugen
# ------------------------------------------------------------

Write-Host ""
Write-Host "Erzeuge Release-Paket..."

# Windows PowerShell 5.1 laedt ZipFile nicht immer automatisch.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$packageName = if ($Variant -eq "cuda") {
    "GLiNER-Runtime-Windows-x64-CUDA.zip"
}
else {
    "GLiNER-Runtime-Windows-x64-CPU.zip"
}

$packagePath = Join-Path $release $packageName
$hashPath = "$packagePath.sha256"

if (Test-Path $packagePath) {
    Remove-Item $packagePath -Force
}

if (Test-Path $hashPath) {
    Remove-Item $hashPath -Force
}

[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $work,
    $packagePath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

if (-not (Test-Path $packagePath)) {
    throw "Release-ZIP wurde nicht erzeugt: $packagePath"
}

$packageHash = (
    Get-FileHash `
        $packagePath `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$hashLine = "$packageHash  $packageName"

[System.IO.File]::WriteAllText(
    $hashPath,
    $hashLine + "`r`n",
    [System.Text.Encoding]::ASCII
)

if (-not (Test-Path $hashPath)) {
    throw "SHA256-Datei wurde nicht erzeugt: $hashPath"
}

$packageSize = (Get-Item $packagePath).Length

Write-Host (
    "ZIP: {0} ({1:N1} MB)" -f `
    $packageName,
    ($packageSize / 1MB)
)

Write-Host "SHA256: $packageHash"

# ------------------------------------------------------------
# ZIP-Inhalt kontrollieren
# ------------------------------------------------------------

Write-Host ""
Write-Host "Pruefe ZIP-Inhalt..."

$zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)

try {
    $zipEntries = @($zip.Entries)

    if ($zipEntries.Count -eq 0) {
        throw "Release-ZIP ist leer."
    }

    $requiredZipEntries = @(
        "gliner/",
        "torch/",
        "transformers/",
        "huggingface_hub/",
        "tokenizers/",
        "safetensors/",
        "sentencepiece/",
        "mediahub-runtime.json"
    )

    foreach ($requiredEntry in $requiredZipEntries) {

        $found = @(
            $zipEntries |
            Where-Object {
                $_.FullName.Replace("\", "/").StartsWith(
                    $requiredEntry,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
        )

        if ($found.Count -eq 0) {
            throw "Pflichtinhalt fehlt im ZIP: $requiredEntry"
        }

        Write-Host "OK - $requiredEntry"
    }

    $forbiddenEntries = @(
        $zipEntries |
        Where-Object {
            $name = $_.FullName.Replace("\", "/")

            $name -match '(^|/)__pycache__(/|$)' -or
            $name -match '(^|/)\.pytest_cache(/|$)' -or
            $name -match '\.py[co]$'
        }
    )

    if ($forbiddenEntries.Count -ne 0) {
        throw (
            "ZIP enthaelt unerlaubte Cache-/Bytecode-Dateien: " +
            $forbiddenEntries.Count
        )
    }
}
finally {
    $zip.Dispose()
}

Write-Host ""
Write-Host "OK - Release-ZIP geprueft."
Write-Host "Release: $packagePath"
Write-Host "SHA256:  $hashPath"

# ------------------------------------------------------------
# CUDA-Release fuer GitHub in mehrere Assets aufteilen
# ------------------------------------------------------------

if ($Variant -eq "cuda") {

    Write-Host ""
    Write-Host "Erzeuge CUDA-Multipart-Release..."

    [int64]$partSize = 1536MB

    Get-ChildItem `
        -LiteralPath $release `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like "$packageName.part*"
        } |
        Remove-Item -Force

    $sourceStream = [System.IO.File]::OpenRead($packagePath)

    try {

        $buffer = New-Object byte[] (8MB)
        $partNumber = 1

        while ($sourceStream.Position -lt $sourceStream.Length) {

            $partName = (
                "{0}.part{1:D3}" -f `
                $packageName,
                $partNumber
            )

            $partPath = Join-Path `
                $release `
                $partName

            Write-Host "Erzeuge $partName ..."

            $partStream = [System.IO.File]::Create($partPath)

            try {

                [int64]$written = 0

                while (
                    $written -lt $partSize -and
                    $sourceStream.Position -lt $sourceStream.Length
                ) {

                    [int]$remaining = [int][Math]::Min(
                        [int64]$buffer.Length,
                        [int64]($partSize - $written)
                    )

                    $read = $sourceStream.Read(
                        $buffer,
                        0,
                        $remaining
                    )

                    if ($read -le 0) {
                        break
                    }

                    $partStream.Write(
                        $buffer,
                        0,
                        $read
                    )

                    $written += $read
                }
            }
            finally {
                $partStream.Dispose()
            }

            $partHash = (
                Get-FileHash `
                    -LiteralPath $partPath `
                    -Algorithm SHA256
            ).Hash.ToLowerInvariant()

            $partHashPath = "$partPath.sha256"

            [System.IO.File]::WriteAllText(
                $partHashPath,
                "$partHash  $partName`r`n",
                [System.Text.Encoding]::ASCII
            )

            Write-Host (
                "OK - {0} ({1:N1} MB)" -f `
                $partName,
                ((Get-Item -LiteralPath $partPath).Length / 1MB)
            )

            Write-Host "SHA256: $partHash"

            $partNumber++
        }
    }
    finally {
        $sourceStream.Dispose()
    }

    $parts = @(
        Get-ChildItem `
            -LiteralPath $release `
            -File |
        Where-Object {
            $_.Name -match (
                "^" +
                [regex]::Escape($packageName) +
                "\.part\d{3}$"
            )
        } |
        Sort-Object Name
    )

    if ($parts.Count -lt 2) {
        throw "CUDA-Multipart erzeugte nur $($parts.Count) Part(s)."
    }

    foreach ($part in $parts) {

        if ($part.Length -ge 2GB) {
            throw "CUDA-Part zu gross: $($part.Name)"
        }

        if (-not (Test-Path -LiteralPath "$($part.FullName).sha256")) {
            throw "SHA256 fehlt fuer $($part.Name)"
        }
    }

    Write-Host ""
    Write-Host "CUDA-Parts: $($parts.Count)"
    Write-Host "CUDA-MULTIPART + SHA256 ERZEUGT"
}

Write-Host "RELEASE-ZIP + SHA256 ERZEUGT"
Write-Host "========================================"




