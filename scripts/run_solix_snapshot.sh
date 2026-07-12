#!/bin/zsh
set -euo pipefail

# Laeuft sowohl aus dem Repo (scripts/) als auch aus dem App-Bundle
# (Contents/Resources/). Pfade sind deshalb relativ zum Script bzw.
# per Umgebungsvariable uebersteuerbar:
#   SOLIXBAR_ENV_FILE  Pfad zur Env-Datei (Default: <repo>/work/solixbar.env)
#   SOLIXBAR_PYTHON    Python-Interpreter (Default: Repo-venv, sonst python3)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${SOLIXBAR_ENV_FILE:-$ROOT_DIR/work/solixbar.env}"
SNAPSHOT_SCRIPT="$SCRIPT_DIR/solix_snapshot.py"

if [[ -n "${SOLIXBAR_PYTHON:-}" ]]; then
  PYTHON="$SOLIXBAR_PYTHON"
elif [[ -x "$ROOT_DIR/work/solix-venv312/bin/python" ]]; then
  PYTHON="$ROOT_DIR/work/solix-venv312/bin/python"
else
  PYTHON="$(command -v python3)"
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# Ertragszustand und API-Cache neben die Env-Datei legen — nie ins
# (signierte) App-Bundle, aus dem das Script laufen kann.
export SOLIXBAR_STATE_PATH="${SOLIXBAR_STATE_PATH:-$(dirname "$ENV_FILE")/energy.json}"
export SOLIXBAR_CACHE_PATH="${SOLIXBAR_CACHE_PATH:-$(dirname "$ENV_FILE")/api-cache.json}"

: "${ANKER_SOLIX_USER:?ANKER_SOLIX_USER fehlt in $ENV_FILE}"
: "${ANKER_SOLIX_PASSWORD:?ANKER_SOLIX_PASSWORD fehlt in $ENV_FILE}"
: "${ANKER_SOLIX_COUNTRY:=DE}"

exec "$PYTHON" "$SNAPSHOT_SCRIPT"
