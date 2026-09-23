# MediaHub Tools

Dieses Repository erstellt und archiviert Windows-Werkzeugpakete und externe Laufzeitkomponenten für MediaHub.

## Aktuell eingerichtet

### Tesseract OCR

- Tesseract OCR für Windows x64
- Paketname: `Tesseract-Projekt.zip`
- automatische Prüfung auf neue offizielle Tesseract-Releases
- zwei gespeicherte Stände: `current` und `previous`

### GLiNER Runtime

Für den MediaHub Compute Node wird eine separate GLiNER-Laufzeit bereitgestellt.

Geplant bzw. vorbereitet sind zwei Varianten:

- `GLiNER-Runtime-Windows-x64-CPU.zip`
- `GLiNER-Runtime-Windows-x64-CUDA.zip`

Die CPU-Variante dient als universelle Windows-x64-Laufzeit und als Fallback.

Die CUDA-Variante ist für kompatible NVIDIA-GPUs vorgesehen und verwendet GPU-Beschleunigung.

Der MediaHub Compute Node bzw. das GLiNER-Plugin soll die geeignete Variante automatisch anhand der tatsächlich verfügbaren Hardware und Laufzeitfähigkeit auswählen. Eine CUDA-Variante darf nur verwendet werden, wenn eine kompatible NVIDIA-/CUDA-Umgebung tatsächlich verfügbar und funktionsfähig ist. Andernfalls wird die CPU-Variante verwendet.

Die GLiNER-Runtime wird nicht in das eigentliche Plugin-Paket eingebettet. Dadurch bleibt das Plugin klein und die große KI-Laufzeit kann getrennt heruntergeladen, aktualisiert und verwaltet werden.

## Tesseract-Ablauf

GitHub prüft nur die Tesseract-Version. Bei einer neuen Version wird aus dem offiziellen Quellcode gebaut, geprüft und veröffentlicht. Erst nach erfolgreichem Release wird `current` nach `previous` verschoben und die neue Version zu `current`.

Es bleiben höchstens zwei Repository-Stände und zwei GitHub-Releases erhalten.

MediaHub-Versionen werden nicht verglichen.

## GLiNER-Ablauf

Die GLiNER-Runtime wird getrennt für CPU und NVIDIA CUDA gebaut und getestet.

Vor einer Veröffentlichung müssen beide Varianten unabhängig geprüft werden.

Zu den Prüfungen gehören insbesondere:

- Python-Import der benötigten Bibliotheken
- GLiNER-Modell laden
- echte GLiNER-Inferenz
- CPU-Ausführung der CPU-Variante
- CUDA-Erkennung der CUDA-Variante
- tatsächliche Modellplatzierung auf der GPU
- tatsächliche GPU-Speichernutzung
- SHA-256-Prüfsumme
- Runtime-Manifest

Die Runtime-Pakete werden getrennt vom eigentlichen MediaHub-Plugin veröffentlicht.

## Drittanbieter

MediaHub Tools enthält bzw. verarbeitet Software und Modelle anderer Projekte.

Die jeweiligen Urheberrechte, Markenrechte und Lizenzrechte verbleiben bei den ursprünglichen Entwicklern und Rechteinhabern.

Weitere Angaben befinden sich in `THIRD_PARTY_LICENSES.md`.
