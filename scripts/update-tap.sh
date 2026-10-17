#!/usr/bin/env bash
#
# Bump the Homebrew cask in a local clone of jeremym/homebrew-tap after a
# release. Rewrites the version and sha256, shows the diff, and stops — it does
# NOT commit or push, so you review and push with your own git/gh credentials
# (browser-OAuth), no tokens or secrets involved.
#
# Usage:
#   scripts/update-tap.sh --tap PATH --version X.Y.Z [--sha256 HEX | --zip FILE]
#
#   --tap      path to your local checkout of jeremym/homebrew-tap
#   --version  the release version (X.Y.Z)
#   --sha256   the zip's sha256 (or pass --zip to read it from the .sha256 file)
#   --zip      path to dist/ClipySecure-X.Y.Z.zip (reads its .sha256 sidecar)

set -euo pipefail

TAP="" ; VERSION="" ; SHA256="" ; ZIP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tap) TAP="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --sha256) SHA256="$2"; shift 2 ;;
        --zip) ZIP="$2"; shift 2 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

[[ -n "$TAP" && -n "$VERSION" ]] || { echo "error: --tap and --version are required" >&2; exit 2; }

if [[ -z "$SHA256" ]]; then
    [[ -n "$ZIP" ]] || { echo "error: pass --sha256 or --zip" >&2; exit 2; }
    SHA256="$(awk '{print $1}' "$ZIP.sha256")"
fi

CASK="$TAP/Casks/clipy-secure.rb"
[[ -f "$CASK" ]] || { echo "error: cask not found at $CASK" >&2; exit 1; }

/usr/bin/sed -i '' -E "s/version \"[^\"]+\"/version \"$VERSION\"/" "$CASK"
/usr/bin/sed -i '' -E "s/sha256 \"[^\"]+\"/sha256 \"$SHA256\"/" "$CASK"

echo "==> Updated $CASK:"
git -C "$TAP" --no-pager diff -- Casks/clipy-secure.rb || true

echo
echo "Optional validation:"
echo "  brew audit --cask --online $CASK"
echo "  brew style $CASK"
echo
echo "Then review and push yourself:"
echo "  git -C \"$TAP\" commit -am \"clipy-secure $VERSION\" && git -C \"$TAP\" push"
