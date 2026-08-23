#!/usr/bin/env bash
#
# Build ClipySecure Release, sign it with the local development certificate,
# install to /Applications and relaunch.
#
# Use this instead of a bare `xcodebuild` for anything you intend to actually
# run. A default xcodebuild invocation signs ad-hoc, which changes the app's
# designated requirement on every build and silently invalidates the
# Accessibility grant — auto-paste then fails with a permission prompt that
# re-granting does not fix. See scripts/create-signing-cert.sh for the details.
#
# Run scripts/create-signing-cert.sh once first.
#
# Env:
#   CODESIGN_IDENTITY   signing identity (default "ClipySecure Development")
#   SKIP_LAUNCH=1       install but do not relaunch

set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:-ClipySecure Development}"
DERIVED="${DERIVED_DATA:-/tmp/clipysecure-local}"
APP_NAME="ClipySecure.app"
INSTALLED="/Applications/$APP_NAME"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "error: no valid code-signing identity named '$IDENTITY'." >&2
    echo "       Run ./scripts/create-signing-cert.sh first." >&2
    exit 1
fi

echo "==> Quitting any running instance"
pkill -x ClipySecure 2>/dev/null || true
sleep 1

echo "==> Building Release signed as '$IDENTITY'"
rm -rf "$DERIVED"
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps com.apple.security.get-task-allow
# (a debug entitlement that lets other processes attach a debugger) out of the
# Release build; Xcode injects it for any non-Developer-ID identity.
xcodebuild \
    -project ClipySecure.xcodeproj \
    -scheme ClipySecure \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

BUILT="$DERIVED/Build/Products/Release/$APP_NAME"

# A cdhash in the designated requirement means the build fell back to ad-hoc
# signing; installing it would break the Accessibility grant again.
DR="$(codesign -d -r- "$BUILT" 2>&1 | tail -1)"
if grep -q "cdhash" <<<"$DR"; then
    echo "error: designated requirement is cdhash-pinned — signing did not take:" >&2
    echo "       $DR" >&2
    exit 1
fi

codesign --verify --strict "$BUILT"

echo "==> Installing to $INSTALLED"
rm -rf "$INSTALLED"
cp -R "$BUILT" /Applications/

echo "==> $DR"

if [[ "${SKIP_LAUNCH:-0}" != "1" ]]; then
    echo "==> Launching"
    open "$INSTALLED"
fi

echo
echo "Done. The Accessibility grant persists across runs of this script."
echo "If macOS still prompts, clear the stale entries once:"
echo "    tccutil reset Accessibility com.clipysecure.app"
