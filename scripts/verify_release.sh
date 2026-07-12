#!/bin/sh
set -eu

# Prüft das gepackte Bundle vor dem Release: Version, Signatur, keine
# privaten Daten, importierbare SOLIX-Module (falls Laufzeit eingebettet).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/outputs/SolixBar.app}"
PLIST="$APP/Contents/Info.plist"
RESOURCES="$APP/Contents/Resources"

test -d "$APP"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [ "$PLIST_VERSION" != "$VERSION" ]; then
  echo "Version passt nicht: VERSION=$VERSION Info.plist=$PLIST_VERSION" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP"

if find "$APP" -type f \( -name '*.env' -o -name 'energy.json' -o -name 'api-cache.json' \
    -o -name 'solixbar-energy.json' -o -name 'solixbar-api-cache.json' \) | grep -q .; then
  echo "Private Laufzeitdaten im App-Bundle gefunden." >&2
  exit 1
fi
if grep -rl "/Users/Basti\|/Users/holger" "$APP" >/dev/null 2>&1; then
  echo "Persönlicher Entwicklungspfad im App-Bundle gefunden." >&2
  echo "(Debug-Binaries enthalten Quellpfade — Release-Binary paketieren: SOLIXBAR_BIN=.build/release/SolixBar)" >&2
  exit 1
fi

if [ -x "$RESOURCES/python/bin/python3.12" ]; then
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$RESOURCES/site-packages" \
    "$RESOURCES/python/bin/python3.12" -c 'import aiohttp, anker_solix_api'
  echo "SOLIX-Laufzeit im Bundle geprüft."
else
  echo "Hinweis: Bundle ohne eingebettete SOLIX-Laufzeit."
fi

echo "SolixBar $VERSION Bundle geprüft."
