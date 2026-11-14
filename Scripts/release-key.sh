#!/bin/bash
# NotchPal, the notch that's alive.
# Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
# SPDX-License-Identifier: GPL-3.0-only
#
# NotchPal's release key: it lives inside this Mac's security chip (Secure Enclave), can't be
# copied off it, and every signature needs Touch ID. NotchPal only installs updates it signed.
#
#   bash Scripts/release-key.sh create       make the key, once (no Touch ID needed yet)
#   bash Scripts/release-key.sh public-key   show the public half, to put in ReleaseSignature.swift
#   bash Scripts/release-key.sh sign         sign the release zip in dist/ (asks for Touch ID)
#   bash Scripts/release-key.sh verify <zip> <version> <sig>
#   bash Scripts/release-key.sh check        prove the signed release passes and fakes fail
#
# Building NotchPal yourself? You don't need any of this. It's only for publishing official releases.
set -euo pipefail
cd "$(dirname "$0")/.."

HELPER="build/release-signer"
SOURCES=(Scripts/release-signer/main.swift Sources/NotchPal/Services/ReleaseSignature.swift)
mkdir -p build
needs_build=0
[[ -x "$HELPER" ]] || needs_build=1
for source in "${SOURCES[@]}"; do
    [[ "$source" -nt "$HELPER" ]] && needs_build=1
done
if [[ "$needs_build" == "1" ]]; then
    swiftc -O "${SOURCES[@]}" -o "$HELPER"
fi

# Proves the check works: the signed zip must pass, and a changed zip or a wrong version must fail.
if [[ "${1:-}" == "check" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)"
    ZIP="dist/NotchPal-$VERSION.zip"
    ok=1
    "$HELPER" verify "$ZIP" "$VERSION" "$ZIP.sig" >/dev/null && echo "PASS: the signed release is accepted" || { echo "FAIL: the signed release was refused"; ok=0; }
    cp "$ZIP" build/tampered.zip && printf 'x' >> build/tampered.zip
    "$HELPER" verify build/tampered.zip "$VERSION" "$ZIP.sig" >/dev/null && { echo "FAIL: a changed download was accepted"; ok=0; } || echo "PASS: a changed download is refused"
    rm -f build/tampered.zip
    "$HELPER" verify "$ZIP" "99.0.0" "$ZIP.sig" >/dev/null && { echo "FAIL: the signature worked for another version"; ok=0; } || echo "PASS: the signature only works for $VERSION"
    printf 'AAAA%s\n' "$(tail -c +5 "$ZIP.sig")" > build/forged.sig
    "$HELPER" verify "$ZIP" "$VERSION" build/forged.sig >/dev/null && { echo "FAIL: a forged signature was accepted"; ok=0; } || echo "PASS: a forged signature is refused"
    rm -f build/forged.sig
    [[ "$ok" == "1" ]] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
    exit 0
fi

if [[ "${1:-}" == "sign" && $# -eq 1 ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)"
    ZIP="dist/NotchPal-$VERSION.zip"
    [[ -f "$ZIP" ]] || { echo "No $ZIP yet. Build first." >&2; exit 1; }
    exec "$HELPER" sign "$ZIP" "$VERSION"
fi
exec "$HELPER" "$@"
