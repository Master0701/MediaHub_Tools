param([Parameter(Mandatory=$true)][string]$Version)
$ErrorActionPreference='Stop'; $Root=Split-Path -Parent $PSScriptRoot; $Base=Join-Path $Root 'packages\tesseract'; $Current=Join-Path $Base 'current'; $Previous=Join-Path $Base 'previous'; $Release=Join-Path $Root 'release'
if(-not(Test-Path(Join-Path $Release 'Tesseract-Projekt.zip'))){throw 'Das neue geprüfte Paket fehlt.'}
Remove-Item $Previous -Recurse -Force -ErrorAction SilentlyContinue; New-Item $Previous -ItemType Directory -Force|Out-Null
if(Test-Path(Join-Path $Current 'manifest.json')){Copy-Item "$Current\*" $Previous -Recurse -Force}
Remove-Item $Current -Recurse -Force -ErrorAction SilentlyContinue; New-Item $Current -ItemType Directory -Force|Out-Null
Copy-Item "$Release\*" $Current -Recurse -Force; Set-Content (Join-Path $Current 'VERSION') $Version -Encoding ASCII
