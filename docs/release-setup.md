# Release setup — one-time runbook

> **Recorded values**
> - Signing identity: `ClipySecure Release` (self-signed, created 2026-10-16, valid 20 years)
> - Certificate leaf hash (SHA-1, as shown by `codesign -d -r-`):
>   `a3ed032a6666d06c91d1c35147ad0e44093c1b5e`
>
> Put this in the README's "Verifying a release" section. A download matches when
> `codesign -d -r- ClipySecure.app` prints
> `certificate leaf = H"a3ed032a6666d06c91d1c35147ad0e44093c1b5e"`.


Releases are **built and signed locally** on your Mac. There is no CI signing,
so the signing key never leaves your machine and there are **no GitHub secrets**
to manage. The only accounts involved are your own `git`/`gh`, which are already
browser-authenticated.

One-time setup has two checkpoint steps (they prompt for your Mac login
password); after that, cutting a release is a handful of local commands.

---

## One-time setup

### 1. Create the release certificate  ⚠️ password prompts

```bash
./scripts/create-release-cert.sh --out ClipySecure-Release
```

Mints the long-lived self-signed **"ClipySecure Release"** identity (20-year
validity) in your login keychain and writes:

- `ClipySecure-Release.p12` — a password-protected **backup** of the key. Store
  it in your password manager and never lose it. If the keychain identity is
  ever lost you restore from this; minting a *new* cert would make every user
  re-approve Gatekeeper and re-grant Accessibility.
- Prints the **certificate leaf SHA-256** — record it in the README so anyone
  can verify a download with `codesign -d -r- ClipySecure.app`.

Delete the `.p12` from disk once it's safely in your password manager (it's
git-ignored, but don't leave the key lying around).

> Why self-signed is enough: TCC keys the Accessibility grant to the designated
> requirement `identifier "com.clipysecure.app" and certificate leaf = H"…"`,
> a hash comparison that doesn't require the cert to be trusted on the user's
> machine. AeroSpace ships this way at scale.

### 2. Point your own machine at the release identity  ⚠️ password + TCC re-grant

So your day-to-day local builds match what users get (identical designated
requirement):

```bash
CODESIGN_IDENTITY="ClipySecure Release" ./scripts/install-local.sh
tccutil reset Accessibility com.clipysecure.app   # one time, then re-grant in System Settings
```

This is the one time switching identities costs a re-grant. After it, both local
`install-local.sh` builds and `brew upgrade` stay stable.

### 3. Create the tap repo (once)

1. Create a public repo `jeremym/homebrew-tap`.
2. Add `Casks/clipy-secure.rb` — copy it from `distribution/clipy-secure.rb` in
   this repo. Keep its `version`/`sha256` lines in their exact shape;
   `scripts/update-tap.sh` rewrites them each release.

Users then install with two lines (no `brew tap`, no trust prompt —
fully-qualified names are self-trusting on Homebrew 6+):

```bash
brew install --cask jeremym/tap/clipy-secure
open -a ClipySecure
```

---

## Cutting a release (repeatable, all local)

From `main`, after merging `develop → main`:

```bash
# 1. Build + sign + package (universal, signed with the release identity)
scripts/build-release.sh --version 1.0.0 --identity "ClipySecure Release"
#    -> dist/ClipySecure-1.0.0.zip (+ .sha256)

# 2. Tag and publish the release with your own gh (browser-authenticated)
git tag v1.0.0 && git push origin v1.0.0
gh release create v1.0.0 \
    dist/ClipySecure-1.0.0.zip dist/ClipySecure-1.0.0.zip.sha256 \
    --title "v1.0.0" --generate-notes

# 3. Bump the Homebrew cask in your local tap clone, then push it yourself
scripts/update-tap.sh --tap ../homebrew-tap --version 1.0.0 \
    --zip dist/ClipySecure-1.0.0.zip
#    review the diff it prints, then:
git -C ../homebrew-tap commit -am "clipy-secure 1.0.0" && git -C ../homebrew-tap push
```

### Verifying a download (put this in the README)

```bash
shasum -a 256 ClipySecure-1.0.0.zip              # matches the release .sha256
codesign -d -r- /Applications/ClipySecure.app    # leaf hash matches the README
```

Integrity rests on the sha256 and the certificate leaf hash — not on Apple
notarization (none) and not on a CI attestation (no CI build).
