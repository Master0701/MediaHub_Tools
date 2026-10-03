#!/usr/bin/env bash
set -euo pipefail

clear

echo "========================================"
echo "MediaHub GLiNER Runtime - Raspberry Pi"
echo "========================================"
echo

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUNTIME_VERSION="$(tr -d '\r\n ' < "$ROOT/tools/gliner-runtime/VERSION")"
GLINER_VERSION="$(tr -d '\r\n ' < "$ROOT/tools/gliner-runtime/GLINER_VERSION")"

WORK="$ROOT/work/gliner-runtime/pi"
SOURCE="$ROOT/work/gliner-runtime/pi-source"
RELEASE="$ROOT/release/gliner-runtime"

PACKAGE_NAME="GLiNER-Runtime-Linux-ARM64-CPU.zip"
PACKAGE="$RELEASE/$PACKAGE_NAME"
HASH_FILE="$PACKAGE.sha256"

MODEL="urchade/gliner_multi-v2.1"

echo "Runtime-Version : $RUNTIME_VERSION"
echo "GLiNER-Version  : $GLINER_VERSION"
echo

# ------------------------------------------------------------
# Plattform pruefen
# ------------------------------------------------------------

ARCH="$(uname -m)"

if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
    echo "FEHLER: ARM64/aarch64 erforderlich. Gefunden: $ARCH"
    exit 1
fi

PYTHON="${PYTHON:-python3}"

PY_VERSION="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

if [[ "$PY_VERSION" != "3.13" ]]; then
    echo "FEHLER: Python 3.13 erforderlich. Gefunden: $PY_VERSION"
    exit 1
fi

echo "Architektur     : $ARCH"
echo "Python          : $("$PYTHON" --version 2>&1)"
echo

# ------------------------------------------------------------
# Werkzeuge pruefen
# ------------------------------------------------------------

for cmd in zip sha256sum find du; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "FEHLER: Benoetigtes Werkzeug fehlt: $cmd"
        exit 1
    fi
done

mkdir -p "$RELEASE"

rm -rf "$SOURCE" "$WORK"
mkdir -p "$SOURCE" "$WORK"

# ------------------------------------------------------------
# Isolierte Source-Runtime erzeugen
# ------------------------------------------------------------

echo "===== SOURCE-RUNTIME ====="
echo

VENV="$ROOT/work/gliner-runtime/pi-build-venv"

rm -rf "$VENV"

"$PYTHON" -m venv "$VENV"

VPY="$VENV/bin/python"

"$VPY" -m pip install --upgrade pip

echo
echo "Installiere Torch ARM64 CPU..."

"$VPY" -m pip install \
    --index-url https://download.pytorch.org/whl/cpu \
    "torch==2.14.0"

echo
echo "Installiere GLiNER und Runtime-Abhaengigkeiten..."

"$VPY" -m pip install \
    --target "$SOURCE" \
    --no-deps \
    "gliner==$GLINER_VERSION"

"$VPY" -m pip install \
    --target "$SOURCE" \
    "transformers" \
    "huggingface_hub" \
    "tokenizers" \
    "safetensors" \
    "sentencepiece" \
    "tiktoken" \
    "protobuf" \
    "numpy"

echo
echo "Kopiere Torch in Source-Runtime..."

TORCH_SITE="$("$VPY" -c 'import torch, pathlib; print(pathlib.Path(torch.__file__).resolve().parent.parent)')"

cp -a "$TORCH_SITE/torch" "$SOURCE/"

while IFS= read -r entry; do
    cp -a "$entry" "$SOURCE/"
done < <(
    find "$TORCH_SITE" -maxdepth 1 \
        \( \
            -name 'torch-*.dist-info' -o \
            -name 'functorch' -o \
            -name 'torchgen' \
        \) \
        -print
)

echo
echo "Installiere Torch-Laufzeitabhaengigkeiten in Source-Runtime..."

"$VPY" -m pip install \
    --target "$SOURCE" \
    "filelock" \
    "fsspec" \
    "jinja2" \
    "networkx" \
    "setuptools" \
    "sympy" \
    "typing-extensions"

# ------------------------------------------------------------
# Source nach Work kopieren
# ------------------------------------------------------------

echo
echo "===== RUNTIME BEREINIGEN ====="
echo

cp -a "$SOURCE/." "$WORK/"

# Python-Bytecode und Caches
find "$WORK" -type d \
    \( -name '__pycache__' -o -name '.pytest_cache' \) \
    -prune -exec rm -rf {} +

find "$WORK" -type f \
    \( -name '*.pyc' -o -name '*.pyo' \) \
    -delete

# Tests/Benchmarks entfernen.
# torch und *.dist-info bleiben geschuetzt.
while IFS= read -r -d '' dir; do

    rel="${dir#"$WORK"/}"
    top="${rel%%/*}"

    if [[ "$top" == "torch" ]]; then
        continue
    fi

    if [[ "$rel" == *".dist-info/"* || "$rel" == *.dist-info ]]; then
        continue
    fi

    rm -rf "$dir"

done < <(
    find "$WORK" -depth -type d \
        \( \
            -name tests -o \
            -name test -o \
            -name testing -o \
            -name benchmarks -o \
            -name benchmark \
        \) \
        -print0
)

# ------------------------------------------------------------
# Pflichtpakete
# ------------------------------------------------------------

echo "===== PFLICHTPAKETE ====="

required=(
    gliner
    torch
    transformers
    huggingface_hub
    tokenizers
    safetensors
    sentencepiece
    tiktoken
    google
)

for package in "${required[@]}"; do

    if [[ ! -e "$WORK/$package" ]]; then
        echo "FEHLER: Pflichtpaket fehlt: $package"
        exit 1
    fi

    echo "OK - $package"
done

# ------------------------------------------------------------
# Manifest
# ------------------------------------------------------------

SIZE="$(du -sb "$WORK" | awk '{print $1}')"

"$PYTHON" - "$WORK/mediahub-runtime.json" "$GLINER_VERSION" "$SIZE" "$MODEL" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, gliner_version, size, model = sys.argv[1:]

manifest = {
    "schema_version": 1,
    "tool": "gliner-runtime",
    "variant": "pi",
    "platform": "linux",
    "architecture": "arm64",
    "gliner_version": gliner_version,
    "torch_version": "2.14.0+cpu",
    "acceleration": "cpu",
    "source_project": "urchade/GLiNER",
    "source_model": model,
    "build_time_utc": datetime.now(timezone.utc).isoformat(),
    "size_bytes": int(size),
}

with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY

echo
echo "Manifest:"
cat "$WORK/mediahub-runtime.json"

# ------------------------------------------------------------
# ZIP + SHA256
# ------------------------------------------------------------

echo
echo "===== RELEASE-PAKET ====="

rm -f "$PACKAGE" "$HASH_FILE"

(
    cd "$WORK"
    zip -q -r "$PACKAGE" .
)

if [[ ! -f "$PACKAGE" ]]; then
    echo "FEHLER: Release-ZIP wurde nicht erzeugt."
    exit 1
fi

(
    cd "$RELEASE"
    sha256sum "$PACKAGE_NAME" > "$PACKAGE_NAME.sha256"
)

# ------------------------------------------------------------
# ZIP kontrollieren
# ------------------------------------------------------------

"$PYTHON" - "$PACKAGE" <<'PY'
import sys
import zipfile

package = sys.argv[1]

required = (
    "gliner/",
    "torch/",
    "transformers/",
    "huggingface_hub/",
    "tokenizers/",
    "safetensors/",
    "sentencepiece/",
    "tiktoken/",
    "mediahub-runtime.json",
)

with zipfile.ZipFile(package) as archive:
    names = [name.replace("\\", "/") for name in archive.namelist()]

    if not names:
        raise SystemExit("FEHLER: Release-ZIP ist leer.")

    for required_entry in required:
        if not any(name.startswith(required_entry) for name in names):
            raise SystemExit(
                f"FEHLER: Pflichtinhalt fehlt im ZIP: {required_entry}"
            )

    forbidden = [
        name for name in names
        if "/__pycache__/" in f"/{name}"
        or "/.pytest_cache/" in f"/{name}"
        or name.endswith(".pyc")
        or name.endswith(".pyo")
    ]

    if forbidden:
        raise SystemExit(
            f"FEHLER: ZIP enthaelt {len(forbidden)} Cache-/Bytecode-Dateien."
        )

print("ZIP-Inhalt OK")
PY

echo
echo "========================================"
echo "PI-RUNTIME ERFOLGREICH"
echo "========================================"
echo
echo "Paket:"
echo "$PACKAGE"
echo
echo "SHA256:"
cat "$HASH_FILE"
echo
du -h "$PACKAGE"

