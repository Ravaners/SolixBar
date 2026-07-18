#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
ARCHIVE="$ROOT/outputs/SolixBar-$VERSION-macOS-arm64.zip"
STAGING="$(mktemp -d "${TMPDIR:-/private/tmp}/solixbar-verify.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT INT TERM
ditto -x -k "$ARCHIVE" "$STAGING"
APP="$STAGING/SolixBar.app"
PLIST="$APP/Contents/Info.plist"

test -f "$ARCHIVE"
test -d "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" -ge 1
codesign --verify --deep --strict --verbose=2 "$APP"

if find "$APP" -type f \( \
  -name '*.env' -o -name '.env*' \
  -o -name 'credentials.enc' -o -name 'credentials.key' \
  -o -name 'energy.json' -o -name 'api-cache.json' \
  -o -name 'history.json' -o -name 'energy-accumulators.json' \
  -o -name 'SolixBar.log' -o -name 'SolixBar.old.log' \
  -o -name 'solixbar-energy.json' -o -name 'solixbar-api-cache.json' \
\) | grep -q .; then
  echo "Private runtime data found in app bundle." >&2
  exit 1
fi
if rg -a -l '/Users/holger|Documents/Codex/2026-07-06' "$APP" >/dev/null; then
  echo "Personal development path found in app bundle." >&2
  exit 1
fi
unzip -t "$ARCHIVE" >/dev/null
if unzip -Z1 "$ARCHIVE" | grep -Eq '(^|/)(__MACOSX|\.DS_Store)(/|$)'; then
  echo "Finder metadata found in release archive." >&2
  exit 1
fi
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$APP/Contents/Resources/site-packages" \
  "$APP/Contents/Resources/python/bin/python3.12" -c 'import aiohttp, anker_solix_api'
echo "Verified SolixBar $VERSION release bundle."
