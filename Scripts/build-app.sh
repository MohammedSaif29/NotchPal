#!/bin/bash
# NotchPal, the notch that's alive.
# Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
# SPDX-License-Identifier: GPL-3.0-only
# Builds NotchPal.app and installs it in your Applications folder (~/Applications).
# Usage: bash Scripts/build-app.sh          (build and install)
#        bash Scripts/build-app.sh --run    (build, install, then open it)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "macOS $(sw_vers -productVersion) · $(swift --version 2>&1 | head -n 1)"
echo "Building NotchPal..."
swift build -c release --product NotchPal
swift build -c release --product NotchPalMediaBridge

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/NotchPal.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchPal" "$APP/Contents/MacOS/NotchPal"
cp "$BIN_DIR/libNotchPalMediaBridge.dylib" "$APP/Contents/Resources/"
cp Support/media-bridge.pl "$APP/Contents/Resources/"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Signing. macOS remembers permissions (Camera, Calendar, Accessibility) by the app's
# signature. An ad-hoc signature ("-") changes on every build, so macOS forgets them each time.
# If you've made a "NotchPal Dev" code-signing certificate in Keychain Access, it's used
# instead and permissions stick between builds. Public releases get a real Developer ID
# signature and Apple notarization.
SIGN_IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "NotchPal Dev"; then
    SIGN_IDENTITY="NotchPal Dev"
fi
sign_app() {
    codesign --force --sign "$1" "$APP/Contents/Resources/libNotchPalMediaBridge.dylib" &&
        codesign --force --sign "$1" "$APP"
}
if [[ "$SIGN_IDENTITY" != "-" ]] && sign_app "$SIGN_IDENTITY"; then
    echo "Signed with: $SIGN_IDENTITY (permissions stay between builds)"
else
    sign_app "-"
    echo "Signed ad-hoc (macOS may ask for permissions again after this build)"
fi

# A zip for GitHub Releases. ditto keeps everything inside the app exactly as macOS expects.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)"
mkdir -p dist
rm -f dist/NotchPal-*.zip
ditto -c -k --keepParent "$APP" "dist/NotchPal-$VERSION.zip"
echo "Release zip: dist/NotchPal-$VERSION.zip"

# Install like a normal app, so login items and permissions work properly.
INSTALL_DIR="$HOME/Applications"
mkdir -p "$INSTALL_DIR"
pkill -x NotchPal 2>/dev/null || true
sleep 0.3
rm -rf "$INSTALL_DIR/NotchPal.app"
cp -R "$APP" "$INSTALL_DIR/NotchPal.app"
echo "Done: $INSTALL_DIR/NotchPal.app"

if [[ "${1:-}" == "--run" ]]; then
    open "$INSTALL_DIR/NotchPal.app"
fi
