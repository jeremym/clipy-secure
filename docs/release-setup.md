# Release setup — one-time runbook

This is the human-in-the-loop half of the release pipeline. Every step here
either prompts for your Mac login password or touches a secret, so **do each one
yourself, at the keyboard** — none of it is safe to automate. The pipeline files
(`scripts/build-release.sh`, `.github/workflows/release.yml`, the versioned
`Info.plist`) are already in the repo and need no secrets to *exist*; they only
need the steps below to *run*.

Do these in order. After this one-time setup, cutting a release is just pushing
a `v*` tag.

---

## 1. Create the release certificate  ⚠️ password prompts

```bash
./scripts/create-release-cert.sh --out ClipySecure-Release
```

This mints the long-lived self-signed **"ClipySecure Release"** identity (20-year
validity) in your login keychain and writes:

- `ClipySecure-Release.p12` — the private key. **Store it in your password
  manager and never lose it.** If it is lost, every user must re-approve the app
  and re-grant Accessibility on the next release.
- `ClipySecure-Release.p12.base64` — base64 of the same, for the GitHub secret.
- It prints the **certificate leaf SHA-256** — record this in the README so
  anyone can verify a download with `codesign -d -r- ClipySecure.app`.

> Why self-signed is enough: TCC keys the Accessibility grant to the designated
> requirement `identifier "com.clipysecure.app" and certificate leaf = H"…"`,
> a hash comparison that does not require the cert to be trusted on the user's
> machine. AeroSpace ships this way at scale.

Delete the two generated files from disk once they are safely in your password
manager and in GitHub secrets (step 2). They are git-ignored, but don't leave
the private key lying around.

## 2. Add the GitHub secrets  ⚠️ secrets

In the `jeremym/clipy-secure` repo → Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `RELEASE_CERT_P12_BASE64` | contents of `ClipySecure-Release.p12.base64` |
| `RELEASE_CERT_PASSWORD` | the password you chose in step 1 |
| `TAP_PUSH_TOKEN` | a fine-grained PAT with **contents: write** on `jeremym/homebrew-tap` only |

## 3. Create the tap repo  ⚠️ repo + token

1. Create a public repo `jeremym/homebrew-tap`.
2. Add `Casks/clipy-secure.rb` — copy it from `distribution/clipy-secure.rb` in
   this repo. (release.yml rewrites its `version`/`sha256` lines each release, so
   keep those two lines exactly as they are.)
3. Optionally add a `.github/workflows/test.yml` that runs `brew audit --cask`
   and `brew style` on the cask.

Install for users then becomes two lines (no `brew tap`, no trust prompt —
fully-qualified names are self-trusting on Homebrew 6+):

```bash
brew install --cask jeremym/tap/clipy-secure
open -a ClipySecure
```

## 4. Point your own machine at the release identity  ⚠️ password + TCC re-grant

So your local builds match what users get (same designated requirement):

```bash
CODESIGN_IDENTITY="ClipySecure Release" ./scripts/install-local.sh
tccutil reset Accessibility com.clipysecure.app   # one time, then re-grant in System Settings
```

This is the one time switching identities costs you a re-grant. After it, both
`brew upgrade` and local `install-local.sh` builds are stable.

---

## Cutting a release (repeatable, no checkpoints)

```bash
# from main, after merging develop -> main
git tag v1.0.0
git push origin v1.0.0
```

`release.yml` then: runs the tests, imports the cert into a temporary keychain
on the runner, builds the signed universal app with `build-release.sh`, attaches
a build-provenance attestation, publishes the GitHub release with the zip +
sha256, and bumps the cask in the tap.

Users can verify any download:

```bash
shasum -a 256 ClipySecure-1.0.0.zip                 # matches the release .sha256
codesign -d -r- /Applications/ClipySecure.app       # leaf hash matches the README
gh attestation verify ClipySecure-1.0.0.zip --owner jeremym
```

## Dry run (optional, local, no secrets)

You can exercise the build without any GitHub involvement once step 1 is done:

```bash
scripts/build-release.sh --version 1.0.0 --identity "ClipySecure Release"
# -> dist/ClipySecure-1.0.0.zip (+ .sha256)
```
