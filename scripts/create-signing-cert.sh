#!/usr/bin/env bash
#
# Create a self-signed code-signing certificate for local development.
#
# Why this exists: ad-hoc signing (`codesign -s -`, what xcodebuild does by
# default) produces a designated requirement pinned to the binary's cdhash:
#
#     designated => cdhash H"8924fd1c11a9ca..."
#
# TCC binds the Accessibility grant to that requirement, so every rebuild looks
# like a brand-new app that merely shares a bundle ID. The old entry stays in
# System Settings pointing at a binary that no longer exists, toggling it does
# nothing, and auto-paste breaks until you reset TCC and re-grant.
#
# Signing with a real certificate — even a self-signed one — makes the
# requirement identity-based instead:
#
#     designated => identifier "com.clipysecure.app" and certificate leaf = H"..."
#
# That is stable across rebuilds, so the grant survives.
#
# This only helps on THIS machine. Gatekeeper still blocks the app elsewhere;
# distribution needs a paid Apple Developer ID plus notarization.
#
# Run once. Then use scripts/install-local.sh to build and install.

set -euo pipefail

IDENTITY="${CODESIGN_IDENTITY:-ClipySecure Development}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "Certificate '$IDENTITY' already exists and is trusted. Nothing to do."
    exit 0
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

echo "==> Generating self-signed certificate (valid 10 years)"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -config "$WORKDIR/cert.cnf" 2>/dev/null

# The Security framework rejects PKCS#12 files using modern MAC/PBE algorithms
# ("MAC verification failed during PKCS12 import"), and rejects a bare PEM key
# ("Unknown format in import"). Legacy SHA1/3DES is the combination it accepts.
echo "==> Packaging as PKCS#12 (legacy algorithms — required by macOS)"
openssl pkcs12 -export \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$WORKDIR/cert.p12" -name "$IDENTITY" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -passout pass:temp 2>/dev/null

echo "==> Importing into the login keychain"
security import "$WORKDIR/cert.p12" -k "$KEYCHAIN" -P temp -A >/dev/null

# Imported but untrusted, the identity reports CSSMERR_TP_NOT_TRUSTED and
# codesign will not use it. This may prompt for your login password.
echo "==> Trusting it for code signing (may prompt for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

echo
if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    security find-identity -v -p codesigning | grep -F "$IDENTITY"
    echo
    echo "Done. Now run: ./scripts/install-local.sh"
else
    echo "Certificate was created but is not showing as valid. Check Keychain Access." >&2
    exit 1
fi
