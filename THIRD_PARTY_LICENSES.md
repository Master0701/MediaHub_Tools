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
