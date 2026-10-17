# ClipySecure

A privacy-first clipboard manager for macOS. Everything you copy is stored encrypted on disk, nothing ever leaves your machine, and the searchable index lives only in memory.

**Website:** [jeremym.github.io/clipy-secure](https://jeremym.github.io/clipy-secure/)

A full rewrite of [Clipy](https://github.com/Clipy/Clipy) in Swift 6, rebuilt around the idea that a clipboard manager sees your passwords, tokens, and private messages — so it should be the last app on your Mac storing them in plain text.

Mostly it exists because I wanted a Clipy with the features I actually use. It's here in case it's useful to anyone else.

![CI](https://github.com/jeremym/clipy-secure/actions/workflows/ci.yml/badge.svg)

## Installing

### Homebrew (recommended)

```bash
brew install --cask jeremym/tap/clipy-secure
open -a ClipySecure
```

That's it — no `brew tap` and no trust flag needed (a fully-qualified cask name is self-trusting on Homebrew 6+). The cask removes the quarantine flag on install, so the app launches without a Gatekeeper prompt, and `brew upgrade` keeps your Accessibility grant across updates. On first run, grant Accessibility when asked — auto-paste needs it.

ClipySecure is signed with the project's own certificate, not an Apple Developer ID, and is **not notarized** (see [below](#why-its-not-notarized)).

### Download the zip

Grab `ClipySecure-X.Y.Z.zip` from the [latest release](https://github.com/jeremym/clipy-secure/releases/latest), unzip it, and move `ClipySecure.app` to `/Applications`. Because it isn't notarized, macOS blocks the first launch:

1. Double-click it — macOS says it can't verify the developer.
2. Open **System Settings → Privacy & Security**, scroll to the "ClipySecure was blocked" notice, and click **Open Anyway**, then authenticate.

Or skip the dialog from Terminal:

```bash
xattr -d com.apple.quarantine /Applications/ClipySecure.app
```

You only do this once per downloaded build.

### Build from source

The "trust nothing" option — compile and sign it yourself:

```bash
git clone https://github.com/jeremym/clipy-secure.git
cd clipy-secure
./scripts/create-signing-cert.sh   # once per machine
./scripts/install-local.sh         # build, sign, install to /Applications, launch
```

`create-signing-cert.sh` generates a self-signed code-signing certificate in your login keychain — no Apple account, no developer membership, created and trusted entirely on your own machine. `install-local.sh` then quits any running copy, builds Release signed with that certificate, checks the signature took, installs to `/Applications`, and launches it.

**Why the certificate step exists.** A plain `xcodebuild` signs ad-hoc, producing a designated requirement pinned to the binary's hash. macOS binds the Accessibility grant to that requirement, so **every rebuild looks like a brand new app**: the old grant goes stale, toggling it in System Settings does nothing, and auto-paste breaks. A certificate — even a self-signed one — makes the requirement identity-based, and the grant survives every rebuild. If a stale grant ever does get stuck, clear it once and re-grant:

```bash
tccutil reset Accessibility com.clipysecure.app
```

## What it does

- **Clipboard history** in the menu bar, up to 32 items by default, covering text, RTF, RTFD, PDF, images, file paths, and URLs.
- **Single-keystroke paste.** Open the menu and press `a` or `b` to paste the two most recent clips, or a digit to open a folder and another digit to paste from it. No Return, no arrow keys.
- **Searchable history panel** with live full-text search and a right-click menu to paste, forget, or delete a clip.
- **Snippets** — reusable text organised in folders, importable and exportable as XML.
- **Memory** — keep clips you want held indefinitely, safe from history expiry, and promote any of them into a snippet folder. A short-term parking lot, not an archive.
- **App exclusion** — name the apps whose clipboard content should never be recorded, such as a password manager.
- Respects the system *concealed* pasteboard flag, so well-behaved password managers are ignored automatically.

## How the privacy works

- **Encrypted at rest.** Clip content — titles, text, RTF, PDF, images, filenames, URLs — is encrypted field-by-field with AES-GCM via CryptoKit before it touches SQLite. The key lives in your Keychain. Plaintext exists only in memory, and the model type cannot persist it even by accident.
- **Keyed content hashes.** Duplicate detection uses HMAC rather than a plain hash, so the database cannot be scanned for known values.
- **The search index never hits disk.** The FTS5 index is built in an attached in-memory database and rebuilt at launch from decrypted rows, so searchable plaintext has nowhere to leak to.
- **No network features.** The app contains no telemetry, sync, update check, or other networking feature. Updates come through `brew upgrade`.
- **Not sandboxed, deliberately.** Auto-paste posts a synthetic ⌘V through CGEvent, which is exactly the cross-application control App Sandbox exists to prevent — a sandboxed build never appears under Accessibility at all. Privacy here comes from encryption, not from the sandbox. This is also why upstream Clipy is not on the Mac App Store.

**One honest exception:** snippets are stored in plain text. They are content you wrote and curate yourself, and they export as plaintext XML by design. Don't keep secrets in them.

## Verifying a release

Each release zip can be checked without trusting anything but the numbers:

```bash
# 1. The download matches the published checksum
shasum -a 256 ClipySecure-X.Y.Z.zip          # compare with the .sha256 in the release

# 2. The app is signed by this project's certificate (not just "some" cert)
codesign -d -r- /Applications/ClipySecure.app
#   expect: designated => identifier "com.clipysecure.app" and certificate leaf = H"a3ed032a6666d06c91d1c35147ad0e44093c1b5e"
```

That leaf hash is the long-lived "ClipySecure Release" certificate. It is the same for every release; if it ever changes, the release notes will say why.

## Why it's not notarized

Notarization requires a paid Apple Developer ID. ClipySecure is a personal project signed with a self-signed certificate instead, the same approach [AeroSpace](https://github.com/nikitabobko/AeroSpace) uses. The practical differences:

- Gatekeeper doesn't recognise the signature, so the Homebrew cask strips the quarantine flag on install (and the zip path needs a one-time "Open Anyway").
- Integrity rests on the published sha256 and the certificate leaf hash above, not on Apple's notary service.
- Because macOS keys the Accessibility grant to the signing identity — which never changes — you grant Accessibility once and it survives every update.

If you'd rather trust nothing at all, build from source.

## Default shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘V | Clip menu at the pointer — history, snippets, and memory |
| ⌃⌘V | Clipboard history search |

Both are rebindable in Preferences, as is the single-key sequence used inside the menu.

## Requirements

- macOS 14 Sonoma or later
- Accessibility permission, granted on first run, for auto-paste
- Xcode 16 or later only if building from source

## Building and testing

```bash
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' build
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' test
```

The test suite runs against an in-memory database with an ephemeral key, so it never touches your Keychain or your real history. It covers CRUD, full-text search, hash stability, snippets, app exclusion, import deduplication, encryption at rest, the encryption migration, menu-shortcut assignment, and regressions from past security fixes.

Releases are built and signed locally — see [`docs/release-setup.md`](docs/release-setup.md).

## Architecture

Swift 6 with strict concurrency. An AppKit shell — status item, windows, menus — hosting SwiftUI views through `NSHostingController`. Clipboard monitoring is an actor polling the pasteboard every 500ms. Storage is GRDB over SQLite, with GRDB `ValueObservation` driving live menu updates; observations deliberately select only lightweight columns, leaving image and document blobs to be fetched on demand at paste time.

Dependencies are Swift Package Manager only: GRDB.swift, KeyboardShortcuts, Defaults, and LaunchAtLogin-Modern.

## License

MIT — see [LICENSE](LICENSE). Upstream [Clipy](https://github.com/Clipy/Clipy), which this rewrite follows, is MIT licensed too.
