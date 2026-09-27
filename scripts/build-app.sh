#!/usr/bin/env bash
# Assemble Mac Vitals into a runnable .app bundle.
#   scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product MacVitals
BIN="$(swift build -c "$CONFIG" --product MacVitals --show-bin-path)/MacVitals"

APP="build/MacVitals.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacVitals"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [ -f scripts/AppIcon.icns ]; then
  cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Companion character packs. SwiftPM emits them as a resource bundle beside the
# binary; the app resolves it under Contents/Resources (a bundle at the .app root
# fails codesign with "unsealed contents present in the bundle root"). Fail the
# build rather than ship an app whose character silently never appears.
BUNDLE="$(dirname "$BIN")/mac-vitals_MacVitals.bundle"
cp -R "$BUNDLE" "$APP/Contents/Resources/"
for pack in rin yuna; do
  test -f "$APP/Contents/Resources/mac-vitals_MacVitals.bundle/Companion/$pack/config.json" \
    || { echo "companion pack '$pack' missing from $APP" >&2; exit 1; }
done

# Ad-hoc signature so a locally built, unnotarized app is allowed to run. A signing
# failure stops the script (it used to be swallowed, which hid exactly the bundle
# placement mistake above).
codesign --force --sign - "$APP"

echo "Built $APP"
