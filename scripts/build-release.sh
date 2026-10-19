#!/usr/bin/env bash
#
# Build a universal (arm64 + x86_64), Release-signed ClipySecure.app and package
# it as ClipySecure-<version>.zip (+ .sha256) in dist/. Releases are cut locally
# (no CI) — run this, create the GitHub release with the zip + sha256, then bump
# version + sha256 in the homebrew-tap cask.
#
# The signing identity MUST be the long-lived "ClipySecure Release" certificate
# (leaf a3ed032a…). Changing it would change the app's designated requirement and
# force every user to re-approve Gatekeeper and re-grant Accessibility — so this
# script verifies the designated requirement is identity-based (never cdhash).
#
# Usage:
#   scripts/build-release.sh --version 1.1.0 [--identity "ClipySecure Release"]
#
# Env:
#   BUILD_NUMBER   CFBundleVersion (default: git commit count)
#   SKIP_TESTS=1   skip the test run (CI runs tests in a separate step)

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=""
IDENTITY="ClipySecure Release"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --identity) IDENTITY="$2"; shift 2 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "error: --version X.Y.Z is required" >&2
    exit 2
fi

BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
DERIVED="/tmp/clipysecure-release"
APP_NAME="ClipySecure.app"
DIST="dist"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "error: no valid code-signing identity named '$IDENTITY'." >&2
    exit 1
fi

echo "==> Building universal Release $VERSION ($BUILD_NUMBER) signed as '$IDENTITY'"
rm -rf "$DERIVED"
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
BINARY="$BUILT/Contents/MacOS/ClipySecure"

echo "==> Verifying the build"

# 1. Both architectures present.
ARCHS_FOUND="$(lipo -archs "$BINARY")"
for arch in arm64 x86_64; do
    grep -qw "$arch" <<<"$ARCHS_FOUND" || { echo "error: missing arch '$arch' (got: $ARCHS_FOUND)" >&2; exit 1; }
done
echo "    archs: $ARCHS_FOUND"

# 2. Designated requirement is identity-based, not cdhash (ad-hoc fallback).
DR="$(codesign -d -r- "$BUILT" 2>&1 | tail -1)"
if grep -q "cdhash" <<<"$DR"; then
    echo "error: designated requirement is cdhash-pinned — signing did not take:" >&2
    echo "       $DR" >&2
    exit 1
fi
echo "    $DR"

# 3. Signature validity.
codesign --verify --strict --deep --verbose=2 "$BUILT"

# 4. Bundle version matches the tag.
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "error: Info.plist version '$BUNDLE_VERSION' != requested '$VERSION'" >&2
    exit 1
fi

echo "==> Packaging"
rm -rf "$DIST"
mkdir -p "$DIST"
ZIP="$DIST/ClipySecure-$VERSION.zip"
# ditto preserves the code signature; `zip` can corrupt it.
ditto -c -k --keepParent "$BUILT" "$ZIP"
shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"

echo
echo "Done:"
echo "    $ZIP"
echo "    $(cat "$ZIP.sha256")  (sha256)"
echo
echo "Next: attach both to the GitHub release, then bump version + sha256 in the"
echo "tap cask (Casks/clipy-secure.rb). Keep the signing identity unchanged."
