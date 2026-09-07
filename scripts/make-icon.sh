#!/usr/bin/env bash
# Render the app icon (docs/design/icon.html) and build scripts/AppIcon.icns.
# Uses headless Chrome for a transparent 1024 master, then sips + iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome not found" >&2; exit 1; }

MASTER="docs/design/icon-1024.png"
rm -f "$MASTER"
TMP="$(mktemp -d)"
"$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
  --hide-scrollbars --default-background-color=00000000 --force-device-scale-factor=1 \
  --window-size=1024,1024 --screenshot="$MASTER" \
  --user-data-dir="$TMP" "file://$PWD/docs/design/icon.html" >/dev/null 2>&1 &
P=$!; for _ in $(seq 1 20); do [ -f "$MASTER" ] && break; sleep 0.5; done; sleep 1
kill "$P" 2>/dev/null || true; pkill -f "Google Chrome.*headless" 2>/dev/null || true
rm -rf "$TMP"
[ -f "$MASTER" ] || { echo "icon render failed" >&2; exit 1; }

ICO="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICO"
sips -z 16 16   "$MASTER" --out "$ICO/icon_16x16.png"     >/dev/null
sips -z 32 32   "$MASTER" --out "$ICO/icon_16x16@2x.png"  >/dev/null
sips -z 32 32   "$MASTER" --out "$ICO/icon_32x32.png"     >/dev/null
sips -z 64 64   "$MASTER" --out "$ICO/icon_32x32@2x.png"  >/dev/null
sips -z 128 128 "$MASTER" --out "$ICO/icon_128x128.png"   >/dev/null
sips -z 256 256 "$MASTER" --out "$ICO/icon_128x128@2x.png">/dev/null
sips -z 256 256 "$MASTER" --out "$ICO/icon_256x256.png"   >/dev/null
sips -z 512 512 "$MASTER" --out "$ICO/icon_256x256@2x.png">/dev/null
sips -z 512 512 "$MASTER" --out "$ICO/icon_512x512.png"   >/dev/null
cp "$MASTER"                   "$ICO/icon_512x512@2x.png"
iconutil -c icns "$ICO" -o scripts/AppIcon.icns
rm -rf "$(dirname "$ICO")"
echo "wrote scripts/AppIcon.icns"
