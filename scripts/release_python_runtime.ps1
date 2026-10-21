param(
    [switch]$Release,
    [switch]$LicenseApproved
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot

$manifestPath = Join-Path $repo "packages\python\current\manifest.json"
$toolPath = Join-Path $repo "tools\python-runtime\tool.json"

Write-Host ""
Write-Host "========================================"
Write-Host "PYTHON RUNTIME RELEASE PREFLIGHT"
Write-Host "========================================"

foreach ($path in @($manifestPath, $toolPath)) {
    switch (Test-Path -LiteralPath $path) {
        $false { throw "Pflichtdatei fehlt: $path" }
    }
}

$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tool = Get-Content $toolPath -Raw -Encoding UTF8 | ConvertFrom-Json

$packagePath = Join-Path $repo ("packages\python\" + $manifest.package)

switch ($manifest.tool -eq "python-runtime") {
    $false { throw "Falsche Tool-ID im Manifest." }
}

switch ($manifest.release_tag -eq "mediahub-tools") {
    $false { throw "Falscher Release-Tag." }
}

switch ($manifest.python_version -eq $tool.python_version) {
    $false { throw "Python-Version stimmt nicht ueberein." }
}

switch ($manifest.version -eq $tool.package_version) {
    $false { throw "Paketversion stimmt nicht ueberein." }
}

switch ($manifest.package -eq $tool.package_name) {
    $false { throw "Paketname stimmt nicht ueberein." }
}

switch (Test-Path -LiteralPath $packagePath) {
    $false { throw "Python-ZIP fehlt: $packagePath" }
}

$package = Get-Item -LiteralPath $packagePath
$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()

switch ([int64]$manifest.size -eq [int64]$package.Length) {
    $false { throw "Paketgroesse stimmt nicht." }
}

switch ($hash -eq ([string]$manifest.sha256).ToLowerInvariant()) {
    $false { throw "Manifest-SHA256 stimmt nicht." }
}

switch ($hash -eq ([string]$tool.package_sha256).ToLowerInvariant()) {
    $false { throw "Tool-SHA256 stimmt nicht." }
}

Write-Host ""
# Original-Lizenzdateien und zentralen Lizenzhinweis pruefen.
Write-Host ""
Write-Host "=== LIZENZDATEIEN PRUEFEN ==="

$licenseFiles = @(
    "THIRD_PARTY_LICENSES.md",
    "licenses/python-runtime/CPython-LICENSE.txt",
    "licenses/python-runtime/CPython-Windows-CRT-LICENSE.txt",
    "licenses/python-runtime/pip-LICENSE.txt",
    "licenses/python-runtime/TclTk-license.terms",
    "licenses/python-runtime/TclTk-demos-license.terms"
)

foreach ($relativePath in $licenseFiles) {
    $licensePath = Join-Path $repo $relativePath

    switch (Test-Path -LiteralPath $licensePath -PathType Leaf) {
        $false { throw "Lizenzdatei fehlt: $relativePath" }
    }

    switch ((Get-Item -LiteralPath $licensePath).Length -gt 0) {
        $false { throw "Lizenzdatei ist leer: $relativePath" }
    }

    Write-Host "OK: $relativePath"
}

$licenseText = Get-Content `
    (Join-Path $repo "THIRD_PARTY_LICENSES.md") `
    -Raw -Encoding UTF8

switch ($licenseText.Contains("Portable Python Runtime 3.12.10")) {
    $false { throw "Python-Eintrag in THIRD_PARTY_LICENSES.md fehlt." }
}

Write-Host "OK: Zentraler Python-Lizenzhinweis"
Write-Host "OK: Python-Version $($manifest.python_version)"
Write-Host "OK: Paketversion $($manifest.version)"
Write-Host "OK: Paket $($manifest.package)"
Write-Host "OK: Groesse $($package.Length) Bytes"
Write-Host "OK: SHA256 $hash"
Write-Host "OK: Release-Tag $($manifest.release_tag)"

Write-Host ""
Write-Host "=== GIT- UND GITHUB-SICHERHEIT ==="

$branch = (git branch --show-current).Trim()

switch ($LASTEXITCODE -eq 0 -and $branch -eq "main") {
    $false { throw "STOP: Release-Vorbereitung nur auf main." }
}

$localHead = (git rev-parse HEAD).Trim()

switch ($LASTEXITCODE -eq 0) {
    $false { throw "Lokaler Git-Commit konnte nicht gelesen werden." }
}

$remoteLine = @(git ls-remote origin refs/heads/main)

switch ($LASTEXITCODE -eq 0 -and $remoteLine.Count -eq 1) {
    $false { throw "GitHub-main konnte nicht gelesen werden." }
}

$remoteHead = ($remoteLine[0] -split "\s+")[0]

switch ($localHead -eq $remoteHead) {
    $false { throw "STOP: Lokaler und GitHub-Commit unterscheiden sich." }
}

$stagedFiles = @(git diff --cached --name-only)

switch ($LASTEXITCODE -eq 0 -and $stagedFiles.Count -eq 0) {
    $false { throw "STOP: Bereits gestagte Dateien vorhanden." }
}

$releaseJson = gh release view mediahub-tools --json tagName,assets

switch ($LASTEXITCODE -eq 0) {
    $false { throw "Gemeinsamer GitHub-Release nicht erreichbar." }
}

$sharedRelease = $releaseJson | ConvertFrom-Json

switch ($sharedRelease.tagName -eq "mediahub-tools") {
    $false { throw "Falscher gemeinsamer Release-Tag." }
}

$assetNames = @($sharedRelease.assets | ForEach-Object { $_.name })

$pythonAssetNames = @(
    [string]$manifest.package,
    "$($manifest.package).sha256",
    "python-runtime-manifest.json"
)

$conflicts = @($pythonAssetNames | Where-Object { $_ -in $assetNames })

switch ($conflicts.Count -eq 0) {
    $false {
        throw "STOP: Python-Assets bereits vorhanden: $($conflicts -join ', ')"
    }
}

$protectedAssetNames = @($assetNames | Sort-Object)

Write-Host "OK: Branch main"
Write-Host "OK: GitHub-main entspricht lokalem HEAD"
Write-Host "OK: Keine fremden gestagten Dateien"
Write-Host "OK: Gemeinsamer Release erreichbar"
Write-Host "OK: Keine Python-Asset-Konflikte"
Write-Host "Geschuetzte vorhandene Assets: $($protectedAssetNames.Count)"

Write-Host ""
Write-Host "=== RELEASE-ASSETS PRUEFEN ==="

$releaseRoot = Join-Path $repo "release\python-runtime"

$hashPath = Join-Path $releaseRoot "$($manifest.package).sha256"
$releaseManifestPath = Join-Path $releaseRoot "python-runtime-manifest.json"

$releaseAssets = @(
    $packagePath,
    $hashPath,
    $releaseManifestPath
)

foreach ($asset in $releaseAssets) {
    switch (Test-Path -LiteralPath $asset -PathType Leaf) {
        $false { throw "Release-Asset fehlt: $asset" }
    }
}

$storedHash = (
    (Get-Content -LiteralPath $hashPath -Raw -Encoding ASCII).Trim() -split '\s+'
)[0].ToLowerInvariant()

switch ($storedHash -eq $hash) {
    $false { throw "STOP: Release-SHA256 stimmt nicht." }
}

$originalManifestHash = (
    Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256
).Hash

$releaseManifestHash = (
    Get-FileHash -LiteralPath $releaseManifestPath -Algorithm SHA256
).Hash

switch ($originalManifestHash -eq $releaseManifestHash) {
    $false { throw "STOP: Release-Manifest ist veraltet." }
}

$assetFileNames = @(
    $releaseAssets | ForEach-Object {
        Split-Path -Leaf $_
    }
)

switch ((@($assetFileNames | Select-Object -Unique)).Count -eq 3) {
    $false { throw "STOP: Doppelte Release-Asset-Namen." }
}

Write-Host "OK: Python-ZIP vorhanden"
Write-Host "OK: SHA256-Datei stimmt"
Write-Host "OK: Release-Manifest aktuell"
Write-Host "OK: Drei eindeutige Release-Assets"

foreach ($assetName in $assetFileNames) {
    Write-Host " - $assetName"
}

Write-Host ""
Write-Host "=== PYTHON-RELEASE-DATEIEN PRUEFEN ==="

$releaseFiles = @(
    ".gitignore",
    "THIRD_PARTY_LICENSES.md",
    "licenses/python-runtime/CPython-LICENSE.txt",
    "licenses/python-runtime/CPython-Windows-CRT-LICENSE.txt",
    "licenses/python-runtime/pip-LICENSE.txt",
    "licenses/python-runtime/TclTk-license.terms",
    "licenses/python-runtime/TclTk-demos-license.terms",
    "packages/python/current/manifest.json",
    "tools/python-runtime/tool.json",
    "scripts/release_python_runtime.ps1",
    "scripts/update_shared_release.ps1"
)

foreach ($relativePath in $releaseFiles) {
    $fullPath = Join-Path $repo $relativePath

    switch (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        $false {
            throw "STOP: Python-Release-Datei fehlt: $relativePath"
        }
    }

    Write-Host "OK: $relativePath"
}

$trackedChanges = @(
    git status --porcelain=v1 --untracked-files=all
)

switch ($LASTEXITCODE -eq 0) {
    $false { throw "Git-Status konnte nicht gelesen werden." }
}

Write-Host ""
Write-Host "Aktuelle Git-Aenderungen:"
$trackedChanges | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "OK: Release-Dateiliste vorbereitet."
Write-Host "Es wurde nichts gestaged oder committed."

Write-Host ""
Write-Host "=== FREMD-AENDERUNGEN PRUEFEN ==="

$changedFiles = @(
    git -c core.quotepath=false ls-files --modified --others --exclude-standard
)

switch ($LASTEXITCODE -eq 0) {
    $false { throw "Git-Aenderungen konnten nicht gelesen werden." }
}

$unexpectedFiles = @(
    $changedFiles |
        Where-Object { $_ -notin $releaseFiles }
)

switch ($unexpectedFiles.Count -eq 0) {
    $true {
        Write-Host "OK: Keine fremden lokalen Aenderungen."
    }
    $false {
        Write-Host "HINWEIS: Fremde lokale Aenderungen vorhanden:"
        $unexpectedFiles | ForEach-Object {
            Write-Host " - $_"
        }
        Write-Host "Diese Dateien duerfen nicht zum Python-Commit gehoeren."
    }
}

Write-Host "OK: Python-Release-Dateiliste bleibt separat."

Write-Host ""
Write-Host "=== GIT-COMMIT-DATEIAUSWAHL ==="

$pythonCommitFiles = @(
    $releaseFiles |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $repo $_) -PathType Leaf
        }
)

switch ($pythonCommitFiles.Count -eq $releaseFiles.Count) {
    $false {
        throw "STOP: Python-Commit-Dateiliste unvollstaendig."
    }
}

$foreignCommitFiles = @(
    $pythonCommitFiles |
        Where-Object { $_ -notin $releaseFiles }
)

switch ($foreignCommitFiles.Count -eq 0) {
    $false {
        throw "STOP: Fremde Dateien in Python-Commit-Dateiliste."
    }
}

Write-Host "OK: $($pythonCommitFiles.Count) freigegebene Python-Dateien."

foreach ($commitFile in $pythonCommitFiles) {
    Write-Host " - $commitFile"
}

Write-Host "OK: Fremde Dateien bleiben ausgeschlossen."
Write-Host "Noch kein git add oder git commit ausgefuehrt."
Write-Host ""
Write-Host "=== GIT-COMMIT-SICHERHEIT ==="

$uniqueCommitFiles = @(
    $pythonCommitFiles | Sort-Object -Unique
)

switch ($uniqueCommitFiles.Count -eq $pythonCommitFiles.Count) {
    $false {
        throw "STOP: Doppelte Python-Commit-Dateien."
    }
}

$alreadyStaged = @(
    git diff --cached --name-only
)

switch ($LASTEXITCODE -eq 0 -and $alreadyStaged.Count -eq 0) {
    $false {
        throw "STOP: Bereits gestagte Dateien vorhanden."
    }
}

Write-Host "OK: Keine doppelten Commit-Dateien."
Write-Host "OK: Git-Index ist leer."
Write-Host "OK: Fremde lokale Aenderungen bleiben unangetastet."

        Write-Host ""
        Write-Host "=== RELEASE-UPLOAD VORBEREITEN ==="

        $uploadFiles = @(
            $packagePath,
            $hashPath,
            $releaseManifestPath
        )

        $uploadNames = @(
            $uploadFiles | ForEach-Object {
                Split-Path -Leaf $_
            }
        )

        switch (
            ($uploadNames.Count -eq 3) -and
            (@($uploadNames | Sort-Object -Unique).Count -eq 3)
        ) {
            $false {
                throw "STOP: Upload-Dateiliste ungueltig."
            }
        }

        foreach ($uploadFile in $uploadFiles) {
            switch (Test-Path -LiteralPath $uploadFile -PathType Leaf) {
                $false {
                    throw "STOP: Upload-Datei fehlt: $uploadFile"
                }
            }
        }

        $foreignUploadNames = @(
            $uploadNames |
                Where-Object { $_ -notin $pythonAssetNames }
        )

        switch ($foreignUploadNames.Count -eq 0) {
            $false {
                throw "STOP: Fremde Dateien im Python-Upload."
            }
        }

        Write-Host "OK: Drei Python-Upload-Dateien vorbereitet."

        foreach ($uploadFile in $uploadFiles) {
            Write-Host " - $uploadFile"
        }

        Write-Host "OK: Keine fremden Tool-Assets im Upload."
        Write-Host "GitHub-Push und Release-Upload bleiben gesperrt."

                Write-Host ""
        Write-Host "=== GITHUB-ASSET-KONFLIKTE ERNEUT PRUEFEN ==="

        $currentReleaseJson = & gh release view mediahub-tools --json assets

        switch ($LASTEXITCODE -eq 0) {
            $false {
                throw "STOP: GitHub-Release konnte nicht gelesen werden."
            }
        }

        $currentRelease = $currentReleaseJson | ConvertFrom-Json

        $currentAssetNames = @(
            $currentRelease.assets |
                ForEach-Object { $_.name }
        )

        $newConflicts = @(
            $uploadNames |
                Where-Object { $_ -in $currentAssetNames }
        )

        switch ($newConflicts.Count -eq 0) {
            $false {
                throw (
                    "STOP: Python-Assets bereits auf GitHub vorhanden: " +
                    ($newConflicts -join ", ")
                )
            }
        }

        $missingProtected = @(
            $protectedAssetNames |
                Where-Object { $_ -notin $currentAssetNames }
        )

        switch ($missingProtected.Count -eq 0) {
            $false {
                throw (
                    "STOP: Bisherige Release-Assets fehlen: " +
                    ($missingProtected -join ", ")
                )
            }
        }

        Write-Host "OK: Keine Python-Asset-Konflikte."
        Write-Host "OK: Alle bisherigen Release-Assets vorhanden."
        Write-Host "OK: $($protectedAssetNames.Count) bestehende Assets geschuetzt."



# A public release is blocked until third-party redistribution rights
# have been checked separately. This flag is an explicit operator attestation.
if ($Release.IsPresent -and -not $LicenseApproved.IsPresent) {
    throw "STOP: Vor oeffentlicher Freigabe Microsoft/Astral-Weitergaberechte pruefen. Danach -LicenseApproved bewusst angeben."
}

# Preserve the current shared tag; never overwrite an unexpected tag update.
$tagLines = @(git ls-remote --tags origin "refs/tags/mediahub-tools")
if ($LASTEXITCODE -ne 0 -or $tagLines.Count -ne 1) {
    throw "STOP: Remote-Release-Tag fehlt oder ist nicht eindeutig."
}
$originalTag = ($tagLines[0] -split '\s+')[0]
$tagCommit = (git rev-parse "refs/tags/mediahub-tools^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $tagCommit -ne $originalTag) {
    throw "STOP: Lokaler und Remote-Release-Tag stimmen nicht ueberein."
}
& git merge-base --is-ancestor $tagCommit HEAD
if ($LASTEXITCODE -ne 0) {
    throw "STOP: Der bisherige Release-Tag ist kein Vorfahr von main."
}

# Shared license asset exists and is the only existing asset we may replace.
if ("THIRD_PARTY_LICENSES.md" -notin $protectedAssetNames) {
    throw "STOP: Gemeinsames Lizenz-Asset fehlt."
}

switch ($Release.IsPresent) {
    $false {
        Write-Host ""
        Write-Host "PREFLIGHT ERFOLGREICH"
        Write-Host "Kein Git-Commit und kein GitHub-Release ausgefuehrt."
    }
    $true {
        Write-Host ""
        Write-Host "=== PYTHON RUNTIME RELEASE ==="
        Write-Host "Ziel: origin/main und vorhandener Release mediahub-tools"
        Write-Host "Python-Assets: $($uploadNames -join ', ')"
        Write-Host "Vorhandene Assets: $($protectedAssetNames.Count)"
        Write-Host "Microsoft/Astral-Lizenzpruefung vom Betreiber bestaetigt."
        $confirmation = Read-Host "Zur Veroeffentlichung exakt RELEASE eingeben"
        if ($confirmation -cne "RELEASE") {
            throw "Release abgebrochen."
        }

        # Re-check remote state immediately before the first mutation.
        $remoteMainNow = @(git ls-remote origin refs/heads/main)
        if ($LASTEXITCODE -ne 0 -or $remoteMainNow.Count -ne 1 -or
            ($remoteMainNow[0] -split '\s+')[0] -ne $localHead) {
            throw "STOP: origin/main hat sich inzwischen geaendert."
        }
        $remoteTagNow = @(git ls-remote --tags origin refs/tags/mediahub-tools)
        if ($LASTEXITCODE -ne 0 -or $remoteTagNow.Count -ne 1 -or
            ($remoteTagNow[0] -split '\s+')[0] -ne $originalTag) {
            throw "STOP: Der gemeinsame Release-Tag hat sich geaendert."
        }

        try {
        Write-Host "=== NUR FREIGEGEBENE DATEIEN STAGEN ==="
        & git add -- $pythonCommitFiles
        if ($LASTEXITCODE -ne 0) { throw "STOP: git add fehlgeschlagen." }

        $staged = @(git -c core.quotepath=false diff --cached --name-only)
        if ($LASTEXITCODE -ne 0 -or $staged.Count -ne $pythonCommitFiles.Count -or
            @($staged | Where-Object { $_ -notin $pythonCommitFiles }).Count -ne 0 -or
            @($pythonCommitFiles | Where-Object { $_ -notin $staged }).Count -ne 0) {
            throw "STOP: Git-Index enthaelt unerwartete Dateien. Kein Commit erstellt."
        }

        & git commit -m "Add portable Python 3.12.10 runtime for Windows Compute Node" --only -- $pythonCommitFiles
        if ($LASTEXITCODE -ne 0) { throw "STOP: Git-Commit fehlgeschlagen." }
        $newHead = (git rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw "STOP: HEAD konnte nicht gelesen werden." }

        $committed = @(git -c core.quotepath=false diff-tree --no-commit-id --name-only -r HEAD)
        if ($LASTEXITCODE -ne 0 -or $committed.Count -ne $pythonCommitFiles.Count -or
            @($committed | Where-Object { $_ -notin $pythonCommitFiles }).Count -ne 0) {
            throw "STOP: Commit enthaelt unerwartete Dateien. Kein Push."
        }

        Write-Host "=== MAIN PUSHEN ==="
        & git push origin "${newHead}:refs/heads/main"
        if ($LASTEXITCODE -ne 0) {
            throw "STOP: Push fehlgeschlagen. Lokaler Commit bleibt erhalten."
        }
        $remoteMainAfter = @(git ls-remote origin refs/heads/main)
        if ($LASTEXITCODE -ne 0 -or ($remoteMainAfter[0] -split '\s+')[0] -ne $newHead) {
            throw "STOP: Remote-main nicht auf erwartetem Commit. Kein Upload."
        }

        Write-Host "=== PYTHON-ASSETS HOCHLADEN ==="
        $releaseBefore = (& gh release view mediahub-tools --json assets | ConvertFrom-Json)
        if ($LASTEXITCODE -ne 0) { throw "STOP: Release nicht lesbar." }
        $namesBefore = @($releaseBefore.assets | ForEach-Object { $_.name })
        if (@($protectedAssetNames | Where-Object { $_ -notin $namesBefore }).Count -ne 0 -or
            @($uploadNames | Where-Object { $_ -in $namesBefore }).Count -ne 0) {
            throw "STOP: GitHub-Assets haben sich geaendert. Kein Upload."
        }

        # No --clobber: never replace existing tool assets.
        & gh release upload mediahub-tools $uploadFiles
        if ($LASTEXITCODE -ne 0) {
            throw "STOP: Python-Upload unvollstaendig oder fehlgeschlagen. Manuell pruefen, nicht blind erneut starten."
        }

        Write-Host "=== GEMEINSAME LIZENZEN AKTUALISIEREN ==="
        $licenseAsset = Join-Path $repo "THIRD_PARTY_LICENSES.md"
        # This is the only deliberate overwrite of an existing release asset.
        & gh release upload mediahub-tools $licenseAsset --clobber
        if ($LASTEXITCODE -ne 0) {
            throw "STOP: Lizenz-Asset konnte nicht aktualisiert werden."
        }

        Write-Host "=== GEMEINSAME RELEASE-BESCHREIBUNG ==="
        $sharedNotesScript = Join-Path $PSScriptRoot "update_shared_release.ps1"
        try {
            & $sharedNotesScript -ReleaseTag "mediahub-tools"

            if (-not $?) {
                throw "Gemeinsames Release-Skript meldet einen Fehler."
            }
        }
        catch {
            throw "STOP: Release-Beschreibung fehlgeschlagen: $($_.Exception.Message)"
        }

        Write-Host "=== RELEASE-TAG KONTROLLIERT AKTUALISIEREN ==="
        $tagBeforePush = @(git ls-remote --tags origin refs/tags/mediahub-tools)
        if ($LASTEXITCODE -ne 0 -or $tagBeforePush.Count -ne 1 -or
            ($tagBeforePush[0] -split '\s+')[0] -ne $originalTag) {
            throw "STOP: Tag wurde zwischenzeitlich geaendert."
        }

        & git tag -f mediahub-tools $newHead
        if ($LASTEXITCODE -ne 0) { throw "STOP: Lokaler Tag konnte nicht gesetzt werden." }
        & git push "--force-with-lease=refs/tags/mediahub-tools:$originalTag" origin refs/tags/mediahub-tools
        if ($LASTEXITCODE -ne 0) {
            throw "STOP: Tag-Push fehlgeschlagen. Bestehenden Release vor weiteren Schritten pruefen."
        }

        Write-Host "=== ABSCHLUSSPRUEFUNG ==="
        $finalTag = @(git ls-remote --tags origin refs/tags/mediahub-tools)
        if ($LASTEXITCODE -ne 0 -or $finalTag.Count -ne 1 -or
            ($finalTag[0] -split '\s+')[0] -ne $newHead) {
            throw "STOP: Release-Tag zeigt nicht auf neuen Commit."
        }
        $finalRelease = (& gh release view mediahub-tools --json assets,body,tagName | ConvertFrom-Json)
        if ($LASTEXITCODE -ne 0) { throw "STOP: Release nicht lesbar." }
        $finalNames = @($finalRelease.assets | ForEach-Object { $_.name })
        $expectedNames = @($protectedAssetNames) + @($uploadNames)
        $missing = @($expectedNames | Where-Object { $_ -notin $finalNames })
        if ($missing.Count -ne 0) {
            throw "STOP: Release-Assets fehlen: $($missing -join ', ')"
        }
        if ($finalRelease.tagName -ne "mediahub-tools" -or
            $finalRelease.body -notmatch "Portable Python Runtime") {
            throw "STOP: Release-Text oder Tag-Name nicht korrekt."
        }

        Write-Host "ERFOLG: Python 3.12.10 veroeffentlicht; vorhandene Assets erhalten."
        Write-Host "Commit/Tag: $newHead"
        }
        catch {
            $releaseError = $_

            Write-Host ""
            Write-Host "=== RELEASE-FEHLERDIAGNOSE ===" -ForegroundColor Yellow
            Write-Host "Fehler: $($releaseError.Exception.Message)"

            Write-Host "`nGitHub-main:"
            & git ls-remote origin refs/heads/main

            Write-Host "`nGitHub-Release-Tag:"
            & git ls-remote --tags origin refs/tags/mediahub-tools

            Write-Host "`nPython-Assets auf GitHub:"
            try {
                $assetInfo = & gh release view mediahub-tools --json assets |
                    ConvertFrom-Json

                $assetInfo.assets |
                    Where-Object {
                        $_.name -like "*Python*" -or
                        $_.name -eq "python-runtime-manifest.json"
                    } |
                    Select-Object name, size |
                    Format-Table -AutoSize
            }
            catch {
                Write-Host "GitHub-Assets konnten nicht gelesen werden."
            }

            Write-Host ""
            Write-Host "STOP: Release moeglicherweise teilweise ausgefuehrt."
            Write-Host "Nicht erneut starten, bevor der GitHub-Zustand geprueft wurde."

            throw $releaseError
        }
    }
}
