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
touch "$APP"

echo "$APP"
