#!/usr/bin/env bash
#
# Create the long-lived, self-signed "ClipySecure Release" code-signing
# certificate used for public builds, and export a password-protected .p12 as a
# backup.
#
# This is the production sibling of create-signing-cert.sh. The difference that
# matters: TCC keys the Accessibility grant to the signature's designated
# requirement, which for a self-signed cert is `identifier + certificate leaf
# hash`. That stays stable across every release ONLY if this one certificate is
# reused forever. Rotating it makes every user re-approve Gatekeeper once and
# re-grant Accessibility once. So: create it once, and never lose the .p12.
#
# Releases are built and signed locally (no CI signing), so the private key
# never leaves this machine — the .p12 is purely your backup. Keep it in your
# password manager; if the keychain identity is lost you restore from it rather
# than minting a new cert (which would cost every user a re-grant).
#
# ⚠️  RUNNING THIS IS A PASSWORD-PROMPT STEP. `security import` and
#     `security add-trusted-cert` will prompt for your Mac login password and
#     change the login keychain. Run it yourself, at the keyboard — not from an
#     unattended agent.
#
# What it produces:
#   - an identity "ClipySecure Release" in your login keychain (valid 20 years)
#   - <output>.p12   password-protected backup (store in your password manager)
#   - prints the certificate leaf SHA-256 to record in the README
#
# Usage:
#   scripts/create-release-cert.sh [--out PATH] [--p12-password PASS]
#   (if --p12-password is omitted you will be prompted)

set -euo pipefail

IDENTITY="ClipySecure Release"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OUT="ClipySecure-Release"
P12_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --p12-password) P12_PASSWORD="$2"; shift 2 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "Identity '$IDENTITY' already exists in the keychain."
    echo "If you need to re-export it, do so from Keychain Access — do NOT create a second one."
    exit 0
fi

if [[ -z "$P12_PASSWORD" ]]; then
    read -r -s -p "Choose a password to protect the exported .p12: " P12_PASSWORD
    echo
    if [[ -z "$P12_PASSWORD" ]]; then
        echo "error: a .p12 password is required (it protects the private key)." >&2
        exit 2
    fi
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = $IDENTITY
[ ext ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
EOF

echo "==> Generating self-signed certificate (valid 20 years)"
openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -config "$WORKDIR/cert.cnf" 2>/dev/null

# The Security framework only accepts PKCS#12 built with legacy SHA1/3DES.
echo "==> Packaging as PKCS#12 for the keychain (legacy algorithms — required by macOS)"
openssl pkcs12 -export \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$WORKDIR/cert.p12" -name "$IDENTITY" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -passout pass:temp 2>/dev/null

echo "==> Importing into the login keychain (may prompt for your password)"
security import "$WORKDIR/cert.p12" -k "$KEYCHAIN" -P temp -A >/dev/null

echo "==> Trusting it for code signing (may prompt for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

# Export a password-protected backup copy, using the same legacy algorithms so
# it can be re-imported later if the keychain identity is ever lost.
echo "==> Exporting password-protected backup .p12 to $OUT.p12"
openssl pkcs12 -export \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$OUT.p12" -name "$IDENTITY" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -passout pass:"$P12_PASSWORD" 2>/dev/null

LEAF_SHA="$(openssl x509 -in "$WORKDIR/cert.pem" -outform DER | shasum -a 256 | awk '{print $1}')"

echo
echo "Done."
echo
echo "  Identity:          $IDENTITY (in your login keychain)"
echo "  Backup (keep safe): $OUT.p12  (store in your password manager — NEVER lose this)"
echo "  Cert leaf SHA-256: $LEAF_SHA  (record in README so downloads can be verified)"
echo
echo "Next (see docs/release-setup.md): switch install-local.sh to this identity"
echo "and re-grant Accessibility once, then build releases locally."
