#!/usr/bin/env bash
# Render the README hero (docs/hero.png) from docs/design/hero.html using headless
# Chrome at 2x. Regenerate this whenever the design changes.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "Google Chrome not found at: $CHROME" >&2
  exit 1
fi

rm -f docs/hero.png
TMP="$(mktemp -d)"
"$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
  --force-device-scale-factor=2 --hide-scrollbars --virtual-time-budget=3500 \
  --window-size=1200,540 --screenshot="docs/hero.png" \
  --user-data-dir="$TMP" "file://$PWD/docs/design/hero.html" >/dev/null 2>&1 &
CPID=$!
for _ in $(seq 1 20); do [ -f docs/hero.png ] && break; sleep 0.5; done
sleep 1
kill "$CPID" 2>/dev/null || true
pkill -f "Google Chrome.*headless" 2>/dev/null || true
rm -rf "$TMP"

[ -f docs/hero.png ] && echo "Wrote docs/hero.png" || { echo "capture failed" >&2; exit 1; }
