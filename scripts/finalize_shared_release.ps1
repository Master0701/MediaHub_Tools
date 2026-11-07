param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$Tag = 'mediahub-tools',
    [switch]$SyncTag
)
cls
$ErrorActionPreference = 'Stop'
$repo = 'Master0701/MediaHub_Tools'
$notes = Join-Path $Root 'scripts\update_shared_release.ps1'
$work = Join-Path $env:TEMP 'MediaHub-Tools-Finalize'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$release = & gh release view $Tag --repo $repo --json assets | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Gemeinsames Release nicht erreichbar.' }
$names = @($release.assets | ForEach-Object { $_.name })
$required = @('Tesseract-Projekt.zip','tesseract-manifest.json','Tesseract-Projekt.zip.sha256','interaktions-ki-manifest.json')
foreach ($item in $required) { if ($item -notin $names) { throw "Release-Asset fehlt: $item" } }
$manifestPath = Join-Path $work 'interaktions-ki-manifest.json'
& gh release download $Tag --repo $repo --pattern 'interaktions-ki-manifest.json' --dir $work --clobber
if ($LASTEXITCODE -ne 0) { throw 'Veroeffentlichtes Interaktions-KI-Manifest nicht abrufbar.' }
$publishedKI = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($publishedKI.status -ne 'release') { throw 'Interaktions-KI-Manifest ist nicht freigegeben.' }
$localTesseract = Get-Content (Join-Path $Root 'packages\tesseract\current\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$publishedTesseractPath = Join-Path $work 'tesseract-manifest.json'
& gh release download $Tag --repo $repo --pattern 'tesseract-manifest.json' --dir $work --clobber
if ($LASTEXITCODE -ne 0) { throw 'Veroeffentlichtes Tesseract-Manifest nicht abrufbar.' }
$publishedTesseract = Get-Content $publishedTesseractPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($localTesseract.version -ne $publishedTesseract.version -or $localTesseract.sha256 -ne $publishedTesseract.sha256) { throw 'STOP: Tesseract-Release und Repository stimmen nicht ueberein.' }
& $notes -SourceRoot $Root -WorkRoot $work -InteraktionsManifestOverride $manifestPath -PreviewOnly
if ($LASTEXITCODE -ne 0 -or -not $?) { throw 'Release-Vorschau fehlgeschlagen.' }
& $notes -SourceRoot $Root -WorkRoot $work -InteraktionsManifestOverride $manifestPath
if ($LASTEXITCODE -ne 0 -or -not $?) { throw 'Release-Text konnte nicht aktualisiert werden.' }
if ($SyncTag) {
    & git -C $Root fetch origin main --no-tags
    if ($LASTEXITCODE -ne 0) { throw 'Git fetch fehlgeschlagen.' }
    $head = (& git -C $Root rev-parse refs/remotes/origin/main).Trim()
    $remoteLine = & git -C $Root ls-remote --refs origin "refs/tags/$Tag"
    if ($LASTEXITCODE -ne 0 -or -not $remoteLine) { throw 'Remote-Tag nicht lesbar.' }
    $old = (($remoteLine | Select-Object -First 1) -split '\s+')[0]
    & git -C $Root fetch origin "refs/tags/$Tag" --no-tags
    if ($LASTEXITCODE -ne 0) { throw 'Tag-Fetch fehlgeschlagen.' }
    & git -C $Root merge-base --is-ancestor $old $head
    if ($LASTEXITCODE -ne 0) { throw 'STOP: Alter Release-Tag ist kein Vorfahr von main.' }
    if ($old -ne $head) {
        # Explizite Lease: Tag nur bewegen, wenn niemand ihn zwischenzeitlich veraendert hat.
        & git -C $Root push origin "${head}:refs/tags/$Tag" "--force-with-lease=refs/tags/${Tag}:$old"
        if ($LASTEXITCODE -ne 0) { throw 'Tag-Synchronisierung abgelehnt. Keine ungeschuetzte Ueberschreibung.' }
    }
    $verify = & git -C $Root ls-remote --refs origin "refs/tags/$Tag"
    $actual = (($verify | Select-Object -First 1) -split '\s+')[0]
    if ($actual -ne $head) { throw 'Tag-Ziel stimmt nicht mit origin/main ueberein.' }
    Write-Host "OK: Release-Tag und main zeigen auf $head"
}
Write-Host 'OK: Release-Beschreibung anhand veroeffentlichter Manifeste aktualisiert.'
