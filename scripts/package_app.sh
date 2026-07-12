#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/outputs/SolixBar.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
BIN="${SOLIXBAR_BIN:-$ROOT/.build/debug/SolixBar}"
cp "$ROOT/Bundle/Info.plist" "$CONTENTS/Info.plist"
# Version aus der VERSION-Datei injizieren — einzige Quelle, damit die
# Anzeige in App/Einstellungen bei jedem Release automatisch stimmt.
if [ -f "$ROOT/VERSION" ]; then
  VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
  BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
fi
cp "$BIN" "$MACOS/SolixBar"
# Debug-Map entfernen: die Symboltabelle enthält sonst absolute
# Quellpfade des Build-Rechners (auch im Release-Build).
strip -S "$MACOS/SolixBar" 2>/dev/null || true
if [ -f "$ROOT/Assets/SolixBar.icns" ]; then
  cp "$ROOT/Assets/SolixBar.icns" "$RESOURCES/SolixBar.icns"
fi
if [ -f "$ROOT/Assets/SolixBar.png" ]; then
  cp "$ROOT/Assets/SolixBar.png" "$RESOURCES/SolixBar.png"
fi
cp "$ROOT/scripts/run_solix_snapshot.sh" "$RESOURCES/run_solix_snapshot.sh"
cp "$ROOT/scripts/solix_snapshot.py" "$RESOURCES/solix_snapshot.py"
chmod +x "$RESOURCES/run_solix_snapshot.sh"
chmod +x "$MACOS/SolixBar"

# Portable SOLIX-Laufzeit einbetten (falls mit prepare_solix_runtime.sh
# vorbereitet): der direkte SOLIX-Modus funktioniert dann ohne lokale
# Python-Installation. Ohne Laufzeit entsteht ein Bundle ohne diesen Modus.
PYTHON_ROOT="$ROOT/work/python"
SITE_PACKAGES="$ROOT/work/solix-venv312/lib/python3.12/site-packages"
if [ -x "$PYTHON_ROOT/bin/python3.12" ] && [ -d "$SITE_PACKAGES/anker_solix_api" ]; then
  cp -R "$PYTHON_ROOT" "$RESOURCES/python"
  cp -R "$SITE_PACKAGES" "$RESOURCES/site-packages"
  # Nicht benötigte Teile entfernen (Header, Tk/Tcl, IDLE, Tests, pip):
  # das spart rund die Hälfte der Laufzeitgrösse.
  rm -rf "$RESOURCES/python/include" "$RESOURCES/python/share"
  for extra in "$RESOURCES/python/lib"/tcl* "$RESOURCES/python/lib"/tk* \
    "$RESOURCES/python/lib"/itcl* "$RESOURCES/python/lib"/thread* \
    "$RESOURCES/python/lib/python3.12/tkinter" \
    "$RESOURCES/python/lib/python3.12/idlelib" \
    "$RESOURCES/python/lib/python3.12/turtledemo" \
    "$RESOURCES/python/lib/python3.12/test" \
    "$RESOURCES/python/lib/python3.12/lib-dynload/_tkinter"*.so; do
    rm -rf "$extra"
  done
  find "$RESOURCES/python/bin" -mindepth 1 ! -name python3.12 -delete
  rm -rf "$RESOURCES/site-packages/pip" "$RESOURCES/site-packages"/pip-*.dist-info
  find "$RESOURCES/python" "$RESOURCES/site-packages" -type d -name __pycache__ -prune -exec rm -rf {} +
  find "$RESOURCES/python" "$RESOURCES/site-packages" -type f -name '*.pyc' -delete
  find "$RESOURCES" -type f -name .DS_Store -delete
  # Import-Probe: schützt vor zu aggressivem Ausdünnen und kaputten Modulen.
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$RESOURCES/site-packages" \
    "$RESOURCES/python/bin/python3.12" -c 'import aiohttp, anker_solix_api' || {
      echo "Eingebettete SOLIX-Module lassen sich nicht importieren." >&2
      exit 1
    }
  find "$RESOURCES/python" "$RESOURCES/site-packages" -type d -name __pycache__ -prune -exec rm -rf {} +
  echo "Portable SOLIX-Laufzeit eingebettet."
else
  echo "Hinweis: keine portable SOLIX-Laufzeit in work/ gefunden — Bundle ohne direkten SOLIX-Modus. Vorbereiten mit: sh scripts/prepare_solix_runtime.sh"
fi

printf "APPL????" > "$CONTENTS/PkgInfo"
# Ad-hoc-Signatur wie in der CI: ohne Signatur zeigt macOS keine
# Benachrichtigungen (UNUserNotificationCenter) an.
xattr -cr "$APP"
codesign --force --deep -s - "$APP"
touch "$APP"

echo "$APP"
