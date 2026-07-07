#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${SOLIXBAR_ENV_FILE:-$ROOT_DIR/work/solixbar.env}"
PYTHON="$ROOT_DIR/work/solix-venv312/bin/python"
SNAPSHOT_SCRIPT="$ROOT_DIR/scripts/solix_snapshot.py"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

: "${ANKER_SOLIX_USER:?ANKER_SOLIX_USER fehlt in $ENV_FILE}"
: "${ANKER_SOLIX_PASSWORD:?ANKER_SOLIX_PASSWORD fehlt in $ENV_FILE}"
: "${ANKER_SOLIX_COUNTRY:=DE}"

exec "$PYTHON" "$SNAPSHOT_SCRIPT"
