#!/bin/bash
# Builds GPTKPatcher as a universal release binary and assembles a runnable .app bundle in build/.
# Usage: scripts/build-app.sh            (then open build/GPTKPatcher.app)
set -euo pipefail
cd "$(dirname "$0")/.."

# The SwiftUI macros need a full Xcode toolchain. If xcode-select points at the bare
# Command Line Tools, borrow the newest Xcode in /Applications for this build only.
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -n 1 || true)"
    if [[ -n "$XCODE" ]]; then
        export DEVELOPER_DIR="$XCODE/Contents/Developer"
        echo "Using toolchain from $XCODE"
    fi
fi

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" 2>&1 | tail -n 2
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/GPTKPatcher"

APP=build/GPTKPatcher.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GPTKPatcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
