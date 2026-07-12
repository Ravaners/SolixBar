#!/bin/sh
set -eu

# Lädt eine portable CPython-Laufzeit (python-build-standalone) nach
# work/python und installiert die SOLIX-Module nach work/solix-venv312.
# Beides bettet scripts/package_app.sh anschliessend ins App-Bundle ein,
# damit der direkte SOLIX-Modus ohne lokale Installation funktioniert.
#
# Übersteuerbar:
#   SOLIXBAR_PBS_RELEASE  python-build-standalone-Release-Tag
#   SOLIXBAR_PBS_ASSET    Tarball-Name (Architektur/Version)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
PYTHON_ROOT="$WORK/python"
VENV="$WORK/solix-venv312"
RELEASE="${SOLIXBAR_PBS_RELEASE:-20260623}"
ASSET="${SOLIXBAR_PBS_ASSET:-cpython-3.12.13+${RELEASE}-aarch64-apple-darwin-install_only.tar.gz}"
URL="https://github.com/astral-sh/python-build-standalone/releases/download/${RELEASE}/${ASSET}"

mkdir -p "$WORK"

if [ ! -x "$PYTHON_ROOT/bin/python3.12" ]; then
  echo "Lade portable Python-Laufzeit: $ASSET"
  TARBALL="$WORK/$ASSET"
  curl -fsSL -o "$TARBALL" "$URL"
  rm -rf "$PYTHON_ROOT"
  # Das Archiv entpackt nach ./python
  tar -xzf "$TARBALL" -C "$WORK"
  rm -f "$TARBALL"
fi
"$PYTHON_ROOT/bin/python3.12" --version

if [ ! -d "$VENV/lib/python3.12/site-packages/anker_solix_api" ]; then
  echo "Installiere SOLIX-Module nach $VENV"
  "$PYTHON_ROOT/bin/python3.12" -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet -r "$ROOT/requirements-solix.txt"
fi

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$VENV/lib/python3.12/site-packages" \
  "$PYTHON_ROOT/bin/python3.12" -c 'import aiohttp, anker_solix_api' \
  || { echo "SOLIX-Module lassen sich nicht importieren." >&2; exit 1; }

echo "SOLIX-Laufzeit bereit: $PYTHON_ROOT + $VENV"
