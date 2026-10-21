# Drittanbieter-Software und Rechte

## Tesseract OCR

- Originalprojekt: Tesseract Open Source OCR Engine
- Quelle: `tesseract-ocr/tesseract`
- Lizenz: Apache License 2.0

## Tesseract-Sprachdaten

- Originalprojekt: tessdata_fast
- Quelle: `tesseract-ocr/tessdata_fast`
- Lizenz: Apache License 2.0

## GLiNER

- Originalprojekt: GLiNER
- Quelle: `urchade/GLiNER`
- Verwendung: Named-Entity-Recognition und KI-Analyse innerhalb der MediaHub-Compute-Node-Erweiterungen
- Lizenz: Apache License 2.0

## GLiNER Modell

- Modell: `gliner_multi-v2.1`
- Quelle: `urchade/gliner_multi-v2.1`
- Verwendung: Modell für die GLiNER-Inferenz

Das Modell ist ein eigenständiges Drittanbieter-Artefakt. Für Modell, Modelldateien und gegebenenfalls zugehörige Daten gelten die vom jeweiligen Herausgeber angegebenen Lizenz- und Nutzungsbedingungen.

## PyTorch

- Originalprojekt: PyTorch
- Verwendung: CPU- und CUDA-Laufzeit für GLiNER

Die GLiNER-Runtime kann abhängig von der Variante unterschiedliche PyTorch-Builds enthalten:

- CPU: `2.14.0+cpu`
- NVIDIA CUDA: `2.14.0+cu126`

Für PyTorch und dessen mitgelieferte Komponenten gelten die jeweiligen Original-Lizenzbedingungen.

## Hugging Face / Transformers-Komponenten

Die GLiNER-Laufzeit verwendet zusätzliche Drittanbieter-Python-Komponenten, unter anderem aus dem Hugging-Face-Ökosystem. Dazu können beispielsweise `transformers`, `huggingface_hub`, `tokenizers` und `safetensors` gehören.

Für diese Komponenten gelten jeweils die Lizenzbedingungen ihrer ursprünglichen Projekte.

## Weitere Runtime-Abhängigkeiten

Die erzeugten GLiNER-Runtime-Pakete enthalten weitere Python-Abhängigkeiten, die zur Ausführung von GLiNER und PyTorch benötigt werden.

Vor einer öffentlichen Veröffentlichung müssen die tatsächlich enthaltenen Pakete und deren Lizenzinformationen aus dem finalen Runtime-Build ermittelt und gegen die mitzuliefernden Drittanbieter- und Lizenzinformationen geprüft werden.

---

MediaHub Tools ist nicht Hersteller oder Eigentümer der oben genannten Drittanbieter-Software, Modelle oder Bibliotheken.

Alle Urheberrechte, Markenrechte, Lizenzrechte und sonstigen Rechte verbleiben vollständig bei den jeweiligen Entwicklern und Rechteinhabern.

Die ursprünglichen Lizenz- und Nutzungsbedingungen gelten unverändert weiter.

## SmolVLM2 500M Video Instruct

- **Component:** SmolVLM2-500M-Video-Instruct model
- **Upstream:** HuggingFaceTB/SmolVLM2-500M-Video-Instruct
- **Developer / provider:** Hugging Face
- **License:** Apache-2.0
- **Bundled in MediaHub plugin:** No
- **Distribution:** Separate MediaHub Tools model package
- **Targets:** Windows Compute Node and Raspberry Pi AI Node
- **Pinned revision:** `7b375e1b73b11138ff12fe22c8f2822d8fe03467`
- **Upstream model page:** https://huggingface.co/HuggingFaceTB/SmolVLM2-500M-Video-Instruct

The upstream SmolVLM2 checkpoints are released under the Apache License 2.0.

MediaHub packages the model separately from the `.mhaiplugin`. Platform-
specific Python, PyTorch, CUDA and other runtime dependencies are not part of
this model package and retain their respective upstream licenses.

See:

`tools/smolvlm2-model/THIRD_PARTY_NOTICE.md`

## Portable Python Runtime 3.12.10 (Windows x64)

- **Software:** CPython 3.12.10
- **Originalprojekt:** Python Software Foundation
- **Originalquelle:** https://www.python.org/
- **Lizenz:** Python Software Foundation License Version 2 sowie die in der Original-Lizenzdatei genannten weiteren Bedingungen
- **Portabler Windows-Build:** Astral / python-build-standalone
- **Build-Projekt:** https://github.com/astral-sh/python-build-standalone
- **Verwendetes Upstream-Archiv:** `cpython-3.12.10+20250409-x86_64-pc-windows-msvc-install_only.tar.gz`
- **MediaHub-Paket:** `packages/python/MediaHub-Python-3.12.10-x64.zip`
- **Zielplattform:** Windows x64
- **Verwendung:** Gemeinsame portable Python-Laufzeit fuer MediaHub Windows Compute Node und kompatible AI-Node-Plugins
- **Installation:** Lokal und parallel zu vorhandenen Python-Installationen; keine systemweite Python-Installation

### Enthaltene Lizenzdateien

Die Original-Lizenztexte sind im Python-Paket enthalten und zusaetzlich unter `licenses/python-runtime/` abgelegt:

- `CPython-LICENSE.txt` - CPython und zugehoerige Lizenzbedingungen
- `pip-LICENSE.txt` - pip 24.3.1
- `TclTk-license.terms` - Tcl/Tk
- `TclTk-demos-license.terms` - Tcl/Tk-Demodateien

### Microsoft Visual C++ Runtime (Windows x64)

- **Hersteller / Rechteinhaber:** Microsoft Corporation
- **Enthaltene Dateien:** `vcruntime140.dll`, `vcruntime140_1.dll`
- **Dateiversion im geprüften Paket:** 14.42.34438.0
- **Herkunft:** Im unveraenderten portablen Windows-Python-Build von Astral enthalten
- **Lizenz:** Microsoft Software License Terms / anwendbare Visual-Studio-Redistributable-Bedingungen; keine Open-Source-Lizenz
- **Microsoft-Dokumentation:** https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170
- **Microsoft-Lizenzverzeichnis:** https://visualstudio.microsoft.com/license-terms/

Die beiden DLLs bleiben Bestandteil des originalen Python-Laufzeitpakets. Die
Microsoft-Signaturen der Dateien wurden geprueft. Eine gueltige Signatur ist
jedoch kein eigenstaendiger Nachweis eines Weitergaberechts. Microsoft knuepft
die Weitergabe der Visual-C++-Runtime-Dateien an die jeweils anwendbaren
Lizenzbedingungen und die erforderliche Lizenzierung des Weitergebenden.
Dieser Hinweis dokumentiert die enthaltenen Komponenten und erteilt keine
zusaetzliche Lizenz. Vor oeffentlicher Weitergabe muss die Berechtigung des
Verteilers geklaert sein. Microsoft-Marken und Copyright-Hinweise bleiben
unveraendert.

### Astral python-build-standalone

- **Build-Projekt:** https://github.com/astral-sh/python-build-standalone
- **Projektlizenz des Build-Werkzeugs:** Mozilla Public License 2.0 (MPL-2.0)
- **Projekt-Lizenztext:** https://github.com/astral-sh/python-build-standalone/blob/main/LICENSE
- **Build-Artefakt:** `cpython-3.12.10+20250409-x86_64-pc-windows-msvc-install_only.tar.gz`

Die MPL-2.0-Angabe betrifft das Build-Projekt und ersetzt nicht die einzelnen
Lizenzen des daraus erzeugten CPython-Pakets, seiner Bibliotheken oder der
Microsoft-Laufzeitdateien. Es gelten jeweils die Originalbedingungen.

Das Python-Paket kann weitere Drittanbieterkomponenten und Windows-Laufzeitbibliotheken enthalten. Deren Original-Lizenz- und Weitergabebedingungen gelten weiterhin, einschliesslich etwaiger Bedingungen fuer Microsoft-Laufzeitdateien.

MediaHub Tools ist weder Hersteller von CPython noch des portablen Astral-Builds. Alle Rechte verbleiben bei den jeweiligen Rechteinhabern.

### CPython Windows Binary Redistribution Conditions

- **Originalquelle:** https://github.com/python/cpython/blob/main/PC/crtlicense.txt
- **Lokale Lizenzdatei:** `licenses/python-runtime/CPython-Windows-CRT-LICENSE.txt`
- **Geltungsbereich:** Microsoft Distributable Code in Windows-Python-Binaerdateien
- **Weitergabe:** Nur unter Einhaltung der im Originaltext genannten Bedingungen.
- **Marken und Urheberrechte:** Originalhinweise duerfen nicht entfernt oder veraendert werden.
- **Plattform:** Microsoft-Laufzeitkomponenten ausschliesslich fuer die erlaubten Microsoft-Plattformen.
- **Empfaenger:** Auch nachgelagerte Verteiler und Endnutzer muessen die einschlaegigen Schutzbedingungen beachten.

