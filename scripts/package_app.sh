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
printf "APPL????" > "$CONTENTS/PkgInfo"
# Ad-hoc-Signatur wie in der CI: ohne Signatur zeigt macOS keine
# Benachrichtigungen (UNUserNotificationCenter) an.
codesign --force --deep -s - "$APP"
touch "$APP"

echo "$APP"
