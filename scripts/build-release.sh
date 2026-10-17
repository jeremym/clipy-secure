#!/usr/bin/env bash
#
# Build a signed, universal Release build of ClipySecure and package it as a zip
# ready to upload to a GitHub release. Releases are built and signed locally (no
# CI signing), so run this on your Mac.
#
# This does NOT create or import any certificate — it signs with an identity
# that must already be in the keychain ("ClipySecure Release", from
# scripts/create-release-cert.sh). It never touches TCC or the login keychain's
# trust settings.
#
# Usage:
#   scripts/build-release.sh --version X.Y.Z [--identity NAME] [--build-number N]
#
# Env (alternatives to flags):
#   CODESIGN_IDENTITY   signing identity (default "ClipySecure Release")
#   DERIVED_DATA        derived-data path (default /tmp/clipysecure-release)
#
# Output: dist/ClipySecure-X.Y.Z.zip  (+ its sha256 printed and written alongside)

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=""
IDENTITY="${CODESIGN_IDENTITY:-ClipySecure Release}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DERIVED="${DERIVED_DATA:-/tmp/clipysecure-release}"
APP_NAME="ClipySecure.app"
OUT_DIR="dist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --identity) IDENTITY="$2"; shift 2 ;;
        --build-number) BUILD_NUMBER="$2"; shift 2 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "error: --version X.Y.Z is required" >&2
    exit 2
fi

# A plain number so Gatekeeper/LaunchServices order builds correctly.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: --version must look like X.Y.Z (got '$VERSION')" >&2
    exit 2
fi

step() { printf '\n==> %s\n' "$1"; }

step "Checking for signing identity '$IDENTITY'"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "error: no valid code-signing identity named '$IDENTITY' in the keychain." >&2
    echo "       Locally, run ./scripts/create-release-cert.sh first." >&2
    exit 1
fi

step "Building universal Release $VERSION (arm64 + x86_64) — first build can take a few minutes"
rm -rf "$DERIVED"
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps the debug entitlement
# com.apple.security.get-task-allow out of Release builds (Xcode injects it for
# any non-Developer-ID identity). ONLY_ACTIVE_ARCH=NO + ARCHS builds both slices.
xcodebuild \
    -project ClipySecure.xcodeproj \
    -scheme ClipySecure \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
if [[ ! -d "$BUILT" ]]; then
    echo "error: build did not produce $BUILT" >&2
    exit 1
fi

step "Verifying the signature"
codesign --verify --strict --deep --verbose=2 "$BUILT"

# A cdhash in the designated requirement means signing fell back to ad-hoc; the
# resulting app would get a fresh identity on every build and break TCC.
DR="$(codesign -d -r- "$BUILT" 2>&1 | tail -1)"
if grep -q "cdhash" <<<"$DR"; then
    echo "error: designated requirement is cdhash-pinned — signing did not take:" >&2
    echo "       $DR" >&2
    exit 1
fi
echo "    designated requirement: $DR"

step "Verifying the binary is universal"
ARCHS_FOUND="$(lipo -archs "$BUILT/Contents/MacOS/ClipySecure")"
echo "    architectures: $ARCHS_FOUND"
for arch in arm64 x86_64; do
    if ! grep -qw "$arch" <<<"$ARCHS_FOUND"; then
        echo "error: missing architecture '$arch' (got: $ARCHS_FOUND)" >&2
        exit 1
    fi
done

step "Verifying the bundle version matches $VERSION"
PLIST="$BUILT/Contents/Info.plist"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "error: Info.plist CFBundleShortVersionString is '$BUNDLE_VERSION', expected '$VERSION'" >&2
    exit 1
fi

step "Packaging dist/ClipySecure-$VERSION.zip"
mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/ClipySecure-$VERSION.zip"
rm -f "$ZIP"
# ditto preserves the code signature in the zip; plain `zip` can corrupt it.
ditto -c -k --keepParent "$BUILT" "$ZIP"

step "Computing sha256"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "$SHA  ClipySecure-$VERSION.zip" > "$ZIP.sha256"
echo "    $SHA"

echo
echo "Done:"
echo "  zip:    $ZIP"
echo "  sha256: $SHA"
echo "  DR:     $DR"
