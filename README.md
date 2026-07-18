# MediaHub Tools

Dieses Repository erstellt und archiviert Windows-Werkzeugpakete für MediaHub vollständig über GitHub Actions.

## Aktuell eingerichtet

- Tesseract OCR für Windows x64
- Paketname: `Tesseract-Projekt.zip`
- automatische Prüfung auf neue offizielle Tesseract-Releases
- zwei gespeicherte Stände: `current` und `previous`

## Ablauf

GitHub prüft nur die Tesseract-Version. Bei einer neuen Version wird aus dem offiziellen Quellcode gebaut, geprüft und veröffentlicht. Erst nach erfolgreichem Release wird `current` nach `previous` verschoben und die neue Version zu `current`. Es bleiben höchstens zwei Repository-Stände und zwei GitHub-Releases erhalten.

MediaHub-Versionen werden nicht verglichen.
