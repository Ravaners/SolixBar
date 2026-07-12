#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
STAGING="$(mktemp -d "${TMPDIR:-/private/tmp}/solixbar-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT INT TERM
APP="$STAGING/SolixBar.app"
ARCHIVE="$ROOT/outputs/SolixBar-$VERSION-macOS-arm64.zip"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
PYTHON_ROOT="$ROOT/work/python"
SITE_PACKAGES="$ROOT/work/solix-venv312/lib/python3.12/site-packages"
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then
  SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
  export SDKROOT
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT/.build/swift-module-cache}"

if [ ! -x "$PYTHON_ROOT/bin/python3.12" ] || [ ! -d "$SITE_PACKAGES/anker_solix_api" ]; then
  echo "Bundled SOLIX runtime is missing. Prepare work/python and work/solix-venv312 first." >&2
  exit 1
fi

swift run -c release --disable-sandbox SolixBarCoreChecks
swift build -c release --disable-sandbox --product SolixBar

mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
cp "$ROOT/Bundle/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/.build/release/SolixBar" "$MACOS/SolixBar"
strip -S "$MACOS/SolixBar"
if [ -f "$ROOT/Assets/SolixBar.icns" ]; then
  cp "$ROOT/Assets/SolixBar.icns" "$RESOURCES/SolixBar.icns"
fi
if [ -f "$ROOT/Assets/SolixBar.png" ]; then
  cp "$ROOT/Assets/SolixBar.png" "$RESOURCES/SolixBar.png"
fi
cp "$ROOT/scripts/solix_snapshot.py" "$RESOURCES/solix_snapshot.py"
cp -R "$PYTHON_ROOT" "$RESOURCES/python"
cp -R "$SITE_PACKAGES" "$RESOURCES/site-packages"
rm -rf "$RESOURCES/python/include" "$RESOURCES/python/share"
rm -rf "$RESOURCES/python/lib/tcl9" "$RESOURCES/python/lib/tcl9.0" \
  "$RESOURCES/python/lib/tk9.0" "$RESOURCES/python/lib/thread3.0.4" \
  "$RESOURCES/python/lib/itcl4.3.5"
find "$RESOURCES/python/bin" -mindepth 1 ! -name python3.12 -delete
rm -rf "$RESOURCES/site-packages/pip" "$RESOURCES/site-packages/pip-"*.dist-info
find "$RESOURCES/python" "$RESOURCES/site-packages" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$RESOURCES/python" "$RESOURCES/site-packages" -type f -name '*.pyc' -delete
find "$RESOURCES" -type f -name .DS_Store -delete
chmod +x "$MACOS/SolixBar"
printf "APPL????" > "$CONTENTS/PkgInfo"

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$RESOURCES/site-packages" \
  "$RESOURCES/python/bin/python3.12" -c 'import aiohttp, anker_solix_api' \
  >/dev/null 2>&1 || {
    echo "Bundled SOLIX Python modules cannot be imported." >&2
    exit 1
  }
find "$RESOURCES/python" "$RESOURCES/site-packages" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$RESOURCES/python" "$RESOURCES/site-packages" -type f -name '*.pyc' -delete
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")"
if [ "$PLIST_VERSION" != "$VERSION" ]; then
  echo "Version mismatch: VERSION=$VERSION Info.plist=$PLIST_VERSION" >&2
  exit 1
fi

rm -f "$ARCHIVE"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ARCHIVE"

echo "$ARCHIVE"
