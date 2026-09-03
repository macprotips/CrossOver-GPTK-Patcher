#!/bin/bash
# Builds a Developer ID-signed, notarized, stapled GPTKPatcher and packages it as a zip in dist/.
# One-time setup (prompts for an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials notary --apple-id you@example.com --team-id MD83L42DNL
# Usage: scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${IDENTITY:-Developer ID Application}"
PROFILE="${NOTARY_PROFILE:-notary}"

scripts/build-app.sh
APP=build/GPTKPatcher.app
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"

echo "Signing with $IDENTITY…"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

mkdir -p dist
ZIP="dist/GPTKPatcher-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple for notarization…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "Stapling…"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"
echo "Ready: $ZIP"
