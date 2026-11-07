param(
    [string]$SourceRoot = 'D:\eigenes program\MediaHub-Tools',
    [string]$WorkRoot = 'D:\eigenes program\cheti sicherungs datein\ki chet',
    [switch]$Release,
    [switch]$ConfirmUpload
)
cls
$ErrorActionPreference = 'Stop'
$repo = 'Master0701/MediaHub_Tools'
$tag = 'mediahub-tools'
$sourceManifest = Join-Path $SourceRoot 'packages\interaktions-ki\current\manifest.json'
$assetDir = Join-Path $SourceRoot 'tools\interaktions-ki'
$stage = Join-Path $WorkRoot 'MediaHub_Tools_Release_Staging\interaktions-ki'
$notesScript = Join-Path $PSScriptRoot 'update_shared_release.ps1'
foreach ($p in @($sourceManifest,$assetDir,$notesScript)) { if (-not (Test-Path -LiteralPath $p)) { throw "Fehlt: $p" } }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'gh.exe fehlt.' }
$m = Get-Content -LiteralPath $sourceManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if ($m.tool -ne 'interaktions-ki') { throw 'Falsches Tool im Manifest.' }
$entries = @($m.runtime.packages.cpu,$m.runtime.packages.cuda,$m.model)
$assets = @()
foreach ($entry in $entries) {
    $name = [string]$entry.package
    if ($name -notmatch '^[A-Za-z0-9_.-]+\.zip$') { throw "Ungueltiger Dateiname: $name" }
    $path = Join-Path $assetDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Fehlendes Archiv: $path" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "SHA256 FEHLER: $name" }
    Write-Host "OK: $name"
    $assets += $path
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
# Nur die veroeffentlichte Kopie wird finalisiert. Die Originalquelle bleibt unveraendert.
$m.version = '0.1.0'
$m.status = 'release'
$m.note = 'Freigegebenes Manifest fuer das MediaHub-Tools-Release; Installation nur nach ausdruecklicher Zustimmung.'
$manifest = Join-Path $stage 'interaktions-ki-manifest.json'
$jsonText = ConvertTo-Json -InputObject $m -Depth 20
[System.IO.File]::WriteAllText($manifest, $jsonText + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
$assets += $manifest
foreach ($entry in $entries) {
    $name = [string]$entry.package
    $checksum = Join-Path $stage ($name + '.sha256')
    [System.IO.File]::WriteAllText($checksum, ([string]$entry.sha256).ToLowerInvariant() + '  ' + $name + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    $assets += $checksum
}
Write-Host 'Release-Manifest: Version 0.1.0, Status release (nur Staging).'
$remoteJson = & gh release view $tag --repo $repo --json assets 2>&1
if ($LASTEXITCODE -ne 0) { throw "Release nicht erreichbar: $remoteJson" }
$remote = @((($remoteJson | ConvertFrom-Json).assets) | ForEach-Object { $_.name })
$missing = @($assets | Where-Object { (Split-Path $_ -Leaf) -notin $remote })
Write-Host "Bereits vorhanden: $($assets.Count - $missing.Count) / $($assets.Count)"
Write-Host "Fehlend: $($missing.Count)"
$missing | ForEach-Object { Write-Host "  $(Split-Path $_ -Leaf)" }
if (-not $Release) {
    & $notesScript -SourceRoot $SourceRoot -WorkRoot $WorkRoot -InteraktionsManifestOverride $manifest -PreviewOnly
    if (-not $?) { throw 'Release-Text-Vorschau fehlgeschlagen.' }
    Write-Host 'VORSCHAU FERTIG: Kein Upload, kein Commit, keine GitHub-Aenderung.'
    return
}
if (-not $ConfirmUpload) { throw 'Freigabe fehlt: -Release und -ConfirmUpload erforderlich.' }
Write-Warning 'Es werden Assets zum bestehenden GitHub-Release hochgeladen und dessen Beschreibung aktualisiert. Kein Git-Commit, kein Tag-Verschieben.'
Write-Warning 'Bereits vorhandene gleichnamige Assets werden nicht ersetzt; deren Inhalt kann hier nicht automatisch bestaetigt werden.'
$approval = Read-Host 'Zur Veroeffentlichung exakt FREIGEBEN eingeben'
if ($approval -cne 'FREIGEBEN') { throw 'Abgebrochen.' }
if ($missing.Count -gt 0) {
    & gh release upload $tag @missing --repo $repo
    if ($LASTEXITCODE -ne 0) { throw 'Upload fehlgeschlagen. Release-Text bleibt unveraendert.' }
}
$verifyJson = & gh release view $tag --repo $repo --json assets 2>&1
if ($LASTEXITCODE -ne 0) { throw 'GitHub-Assets nach Upload nicht lesbar.' }
$verifiedNames = @((($verifyJson | ConvertFrom-Json).assets) | ForEach-Object { $_.name })
$notUploaded = @($assets | Where-Object { (Split-Path $_ -Leaf) -notin $verifiedNames })
if ($notUploaded.Count -gt 0) { throw "Assets fehlen nach Upload: $($notUploaded -join ', '). Release-Text bleibt unveraendert." }
& $notesScript -SourceRoot $SourceRoot -WorkRoot $WorkRoot -InteraktionsManifestOverride $manifest -PreviewOnly
if (-not $?) { throw 'Vorschau fehlgeschlagen; Release-Text bleibt unveraendert.' }
& $notesScript -SourceRoot $SourceRoot -WorkRoot $WorkRoot -InteraktionsManifestOverride $manifest
if (-not $?) { throw 'Release-Text konnte nicht aktualisiert werden.' }
Write-Host 'FERTIG: Sieben Assets vorhanden und gemeinsamer Release-Text aktualisiert.'
