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

# Ad-hoc signature so a locally built, unnotarized app is allowed to run.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
