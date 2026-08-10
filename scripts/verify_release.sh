#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
ARCHIVE="$ROOT/outputs/SolixBar-$VERSION-macOS-arm64.zip"
STAGING="$(mktemp -d "${TMPDIR:-/private/tmp}/solixbar-verify.XXXXXX")"
cleanup() {
  chmod -R u+w "$STAGING" 2>/dev/null || true
  rm -rf "$STAGING"
}
trap cleanup EXIT INT TERM
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
if find "$APP" \( -type d -name authcache -o -type d -name __pycache__ -o -type f -name '*.pyc' \) | grep -q .; then
  echo "Authentication or Python cache found in app bundle." >&2
  exit 1
fi
if rg -a -l '/Users/[^/]+/(Desktop|Documents|Downloads)/|Documents/Codex/' "$APP" >/dev/null; then
  echo "Personal development path found in app bundle." >&2
  exit 1
fi
if unzip -Z1 "$ARCHIVE" | grep -Eqi '(^|/)(authcache|__pycache__)(/|$)|\.pyc$'; then
  echo "Authentication or Python cache found in release archive." >&2
  exit 1
fi
unzip -t "$ARCHIVE" >/dev/null
if unzip -Z1 "$ARCHIVE" | grep -Eq '(^|/)(__MACOSX|\.DS_Store)(/|$)'; then
  echo "Finder metadata found in release archive." >&2
  exit 1
fi
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$APP/Contents/Resources/site-packages" \
  "$APP/Contents/Resources/python/bin/python3.12" -c 'import aiohttp, anker_solix_api'
python3 "$ROOT/scripts/localization_checks.py"
echo "Verified SolixBar $VERSION release bundle."
