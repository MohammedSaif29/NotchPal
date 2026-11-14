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

# Signing. macOS remembers permissions (Camera, Calendar, Accessibility) by the app's
# signature. An ad-hoc signature ("-") changes on every build, so macOS forgets them each time.
# If you've made a "NotchPal Dev" code-signing certificate in Keychain Access, it's used
# instead and permissions stick between builds. Public releases get a real Developer ID
# signature and Apple notarization.
SIGN_IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "NotchPal Dev"; then
    SIGN_IDENTITY="NotchPal Dev"
fi

# Puts the built files together into an app at $2, and signs it.
make_app() {
    local bin="$1" app="$2"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin/NotchPal" "$app/Contents/MacOS/NotchPal"
    cp "$bin/libNotchPalMediaBridge.dylib" "$app/Contents/Resources/"
    cp Support/media-bridge.pl "$app/Contents/Resources/"
    cp Support/Info.plist "$app/Contents/Info.plist"
    # Readable by everyone, and no leftover Finder or download tags, so the app is the same on every Mac.
    chmod -R u+rwX,go+rX "$app"
    xattr -cr "$app" 2>/dev/null || true
    sign() {
        codesign --force --sign "$1" "$app/Contents/Resources/libNotchPalMediaBridge.dylib" &&
            codesign --force --sign "$1" "$app"
    }
    if [[ "$SIGN_IDENTITY" != "-" ]] && sign "$SIGN_IDENTITY"; then
        echo "Signed with: $SIGN_IDENTITY (permissions stay between builds)"
    else
        sign "-"
        echo "Signed ad-hoc (macOS may ask for permissions again after this build)"
    fi
}

APP="build/NotchPal.app"
make_app "$BIN_DIR" "$APP"

# A zip for GitHub Releases. ditto keeps everything inside the app exactly as macOS expects.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)"
mkdir -p dist
rm -f dist/NotchPal-*.zip dist/NotchPal-*.zip.sig
ditto -c -k --norsrc --noextattr --keepParent "$APP" "dist/NotchPal-$VERSION.zip"
echo "Release zip: dist/NotchPal-$VERSION.zip"

# Official releases only: a ".sign-release" file asks for this zip to be signed with the release
# key in this Mac's security chip (see Scripts/release-key.sh). Touch ID is asked for here.
if [[ -f .sign-release ]]; then
    rm -f .sign-release
    if bash Scripts/release-key.sh sign; then
        echo "RELEASE SIGNED"
        bash Scripts/release-key.sh check || true
    else
        echo "RELEASE NOT SIGNED"
    fi
fi

# A personal copy for this Mac only, with extras from Sources/NotchPal/Personal. It's built
# separately, so the release zip above never contains them. Turned on by a ".personal" file.
INSTALL_APP="$APP"
if [[ "${NOTCHPAL_PERSONAL:-}" == "1" ]]; then
    echo "Building your personal copy (not in the release zip)..."
    swift build -c release --product NotchPal --scratch-path .build-personal -Xswiftc -DNOTCHPAL_PERSONAL
    swift build -c release --product NotchPalMediaBridge --scratch-path .build-personal
    make_app "$(swift build -c release --scratch-path .build-personal --show-bin-path)" "build/NotchPal-personal.app"
    INSTALL_APP="build/NotchPal-personal.app"
fi

# Install like a normal app, so login items and permissions work properly.
INSTALL_DIR="$HOME/Applications"
mkdir -p "$INSTALL_DIR"
pkill -x NotchPal 2>/dev/null || true
sleep 0.3
rm -rf "$INSTALL_DIR/NotchPal.app"
cp -R "$INSTALL_APP" "$INSTALL_DIR/NotchPal.app"
echo "Done: $INSTALL_DIR/NotchPal.app"

if [[ "${1:-}" == "--run" ]]; then
    open "$INSTALL_DIR/NotchPal.app"
fi
