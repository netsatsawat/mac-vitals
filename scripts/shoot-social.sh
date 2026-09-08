#!/usr/bin/env bash
# Render the GitHub social preview card (docs/social-preview.png, 1280x640) from
# docs/design/social.html using headless Chrome. Upload it under the repo's
# Settings, Social preview. Regenerate whenever the design changes.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "Google Chrome not found at: $CHROME" >&2
  exit 1
fi

rm -f docs/social-preview.png
TMP="$(mktemp -d)"
"$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
  --hide-scrollbars --virtual-time-budget=3500 \
  --window-size=1280,640 --screenshot="docs/social-preview.png" \
  --user-data-dir="$TMP" "file://$PWD/docs/design/social.html" >/dev/null 2>&1 &
CPID=$!
for _ in $(seq 1 20); do [ -f docs/social-preview.png ] && break; sleep 0.5; done
sleep 1
kill "$CPID" 2>/dev/null || true
pkill -f "Google Chrome.*headless" 2>/dev/null || true
rm -rf "$TMP"

[ -f docs/social-preview.png ] && echo "Wrote docs/social-preview.png" || { echo "capture failed" >&2; exit 1; }
