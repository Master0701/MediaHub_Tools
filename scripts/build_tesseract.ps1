param([Parameter(Mandatory=$true)][string]$Version)
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
$Root=Split-Path -Parent $PSScriptRoot; $Work=Join-Path $Root 'work\tesseract'; $Source=Join-Path $Work 'source'; $Vcpkg=Join-Path $Work 'vcpkg'; $Build=Join-Path $Source 'build'; $Stage=Join-Path $Work 'stage'; $Release=Join-Path $Root 'release'
Remove-Item $Work,$Release -Recurse -Force -ErrorAction SilentlyContinue
New-Item $Work,$Stage,$Release -ItemType Directory -Force|Out-Null
$tag=$Version.TrimStart('v')
git clone --depth 1 --branch $tag --recurse-submodules https://github.com/tesseract-ocr/tesseract.git $Source
if($LASTEXITCODE-ne 0){throw 'Tesseract-Quellcode konnte nicht geladen werden.'}
git clone --depth 1 https://github.com/microsoft/vcpkg.git $Vcpkg
& "$Vcpkg\bootstrap-vcpkg.bat" -disableMetrics
if($LASTEXITCODE-ne 0){throw 'vcpkg bootstrap fehlgeschlagen.'}
& "$Vcpkg\vcpkg.exe" install leptonica:x64-windows
if($LASTEXITCODE-ne 0){throw 'Leptonica-Build fehlgeschlagen.'}
cmake -S $Source -B $Build -A x64 -DCMAKE_BUILD_TYPE=Release -DSW_BUILD=OFF -DOPENMP_BUILD=OFF -DBUILD_TRAINING_TOOLS=OFF -DBUILD_TESTS=OFF "-DCMAKE_TOOLCHAIN_FILE=$Vcpkg\scripts\buildsystems\vcpkg.cmake"
if($LASTEXITCODE-ne 0){throw 'CMake-Konfiguration fehlgeschlagen.'}
cmake --build $Build --config Release --target tesseract
if($LASTEXITCODE-ne 0){throw 'Tesseract-Build fehlgeschlagen.'}
$Exe=Get-ChildItem $Build -Filter tesseract.exe -Recurse|Select-Object -First 1 -ExpandProperty FullName
if(-not $Exe){throw 'tesseract.exe wurde nicht gefunden.'}
Copy-Item $Exe $Stage
$VcpkgBin=Join-Path $Vcpkg 'installed\x64-windows\bin'; if(Test-Path $VcpkgBin){Copy-Item "$VcpkgBin\*.dll" $Stage -Force}
$Tessdata=Join-Path $Stage 'tessdata'; New-Item $Tessdata -ItemType Directory -Force|Out-Null
$headers=@{'User-Agent'='MediaHub-Tools'}
foreach($lang in @('deu','eng','osd')){Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/$lang.traineddata" -Headers $headers -OutFile (Join-Path $Tessdata "$lang.traineddata")}
Copy-Item (Join-Path $Source 'LICENSE') (Join-Path $Stage 'LICENSE-TESSERACT.txt')
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/LICENSE' -Headers $headers -OutFile (Join-Path $Stage 'LICENSE-TESSDATA_FAST.txt')
Copy-Item (Join-Path $Root 'THIRD_PARTY_LICENSES.md') $Stage
$out=& (Join-Path $Stage 'tesseract.exe') --version 2>&1
if($LASTEXITCODE-ne 0 -or (($out|Out-String)-notmatch [regex]::Escape($tag))){throw "Versionsprüfung fehlgeschlagen: $out"}
$manifest=[ordered]@{tool='tesseract';display_name='Tesseract OCR';version=$tag;architecture='x64';package='Tesseract-Projekt.zip';executable='tesseract.exe';languages=@('deu','eng','osd');source_repository='https://github.com/tesseract-ocr/tesseract';source_tag=$tag;language_repository='https://github.com/tesseract-ocr/tessdata_fast';license='Apache-2.0';built_at_utc=(Get-Date).ToUniversalTime().ToString('o')}
$manifest|ConvertTo-Json -Depth 10|Set-Content (Join-Path $Stage 'manifest.json') -Encoding UTF8
$Zip=Join-Path $Release 'Tesseract-Projekt.zip'; Compress-Archive -Path "$Stage\*" -DestinationPath $Zip -CompressionLevel Optimal
$Test=Join-Path $Work 'zip-test'; Expand-Archive $Zip $Test -Force
foreach($r in @('tesseract.exe','manifest.json','LICENSE-TESSERACT.txt','LICENSE-TESSDATA_FAST.txt','tessdata\deu.traineddata','tessdata\eng.traineddata','tessdata\osd.traineddata')){if(-not(Test-Path(Join-Path $Test $r))){throw "ZIP-Prüfung fehlgeschlagen: $r fehlt."}}
& (Join-Path $Test 'tesseract.exe') --version|Out-Host; if($LASTEXITCODE-ne 0){throw 'ZIP-Programmtest fehlgeschlagen.'}
$Hash=(Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant(); "$Hash  Tesseract-Projekt.zip"|Set-Content (Join-Path $Release 'Tesseract-Projekt.zip.sha256') -Encoding ASCII
[ordered]@{tool='tesseract';version=$tag;package='Tesseract-Projekt.zip';sha256=$Hash;release_tag="tesseract-v$tag";built_at_utc=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $Release 'manifest.json') -Encoding UTF8
