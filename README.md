# ClipySecure

A privacy-first clipboard manager for macOS. Everything you copy is stored encrypted on disk, nothing ever leaves your machine, and the searchable index lives only in memory.

A full rewrite of [Clipy](https://github.com/Clipy/Clipy) in Swift 6, rebuilt around the idea that a clipboard manager sees your passwords, tokens, and private messages — so it should be the last app on your Mac storing them in plain text.

![CI](https://github.com/jeremym/clipy-secure/actions/workflows/ci.yml/badge.svg)

## What it does

- **Clipboard history** in the menu bar, up to 32 items by default, covering text, RTF, RTFD, PDF, images, file paths, and URLs.
- **Single-keystroke paste.** Open the menu and press `a` or `b` to paste the two most recent clips, or a digit to open a folder and another digit to paste from it. No Return, no arrow keys.
- **Searchable history panel** with live full-text search.
- **Snippets** — reusable text organised in folders, importable and exportable as XML.
- **Memory** — pin clips you want kept indefinitely, safe from history expiry, and promote any of them into a snippet folder.
- **App exclusion** — name the apps whose clipboard content should never be recorded, such as a password manager.
- Respects the system *concealed* pasteboard flag, so well-behaved password managers are ignored automatically.

## How the privacy works

- **Encrypted at rest.** Clip content — titles, text, RTF, PDF, images, filenames, URLs — is encrypted field-by-field with AES-GCM via CryptoKit before it touches SQLite. The key lives in your Keychain. Plaintext exists only in memory, and the model type cannot persist it even by accident.
- **Keyed content hashes.** Duplicate detection uses HMAC rather than a plain hash, so the database cannot be scanned for known values.
- **The search index never hits disk.** The FTS5 index is built in an attached in-memory database and rebuilt at launch from decrypted rows, so searchable plaintext has nowhere to leak to.
- **No network, by construction.** The app requests no network entitlement. There is no telemetry, no sync, no update check.
- **Not sandboxed, deliberately.** Auto-paste posts a synthetic ⌘V through CGEvent, which is exactly the cross-application control App Sandbox exists to prevent — a sandboxed build never appears under Accessibility at all. Privacy here comes from encryption, not from the sandbox. This is also why upstream Clipy is not on the Mac App Store.

**One honest exception:** snippets are stored in plain text. They are content you wrote and curate yourself, and they export as plaintext XML by design. Don't keep secrets in them.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later to build
- Accessibility permission, granted on first run, for auto-paste

## Installing

There are no downloadable releases. Distributing a macOS app that other people can open requires an Apple Developer ID and notarization, which this project does not have yet — a downloaded build would simply be blocked by Gatekeeper. **Build it from source instead.**

```bash
git clone https://github.com/jeremym/clipy-secure.git
cd clipy-secure
./scripts/create-signing-cert.sh   # once per machine
./scripts/install-local.sh         # build, sign, install to /Applications, launch
```

The signing script matters more than it looks. A plain `xcodebuild` produces an ad-hoc signature whose designated requirement is pinned to the binary's hash, and macOS binds the Accessibility grant to that requirement — so **every rebuild looks like a brand new app**, the old grant goes stale, and auto-paste silently breaks. Signing with a self-signed certificate makes the requirement identity-based and therefore stable across rebuilds.

If a stale grant ever gets stuck:

```bash
tccutil reset Accessibility com.clipysecure.app
```

The certificate is local to your machine. Gatekeeper will still block the app on anyone else's.

## Default shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘V | Clip menu at the pointer — history, snippets, and memory |
| ⌃⌘V | History panel with search |
| ⇧⌘B | Snippets menu |

All three are rebindable in Preferences.

## Building and testing

```bash
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' build
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' test
```

The test suite runs against an in-memory database with an ephemeral key, so it never touches your Keychain or your real history. It covers CRUD, full-text search, hash stability, snippets, app exclusion, import deduplication, encryption at rest, the encryption migration, and regressions from past security fixes.

## Architecture

Swift 6 with strict concurrency. An AppKit shell — status item, windows, menus — hosting SwiftUI views through `NSHostingController`. Clipboard monitoring is an actor polling the pasteboard every 500ms. Storage is GRDB over SQLite, with GRDB `ValueObservation` driving live menu updates; observations deliberately select only lightweight columns, leaving image and document blobs to be fetched on demand at paste time.

Dependencies are Swift Package Manager only: GRDB.swift, KeyboardShortcuts, Defaults, and LaunchAtLogin-Modern.

## Status

Feature-complete and in daily use by its author, but it has not been through external review, has no notarized build, and has no release process yet. Treat it as working software you compile yourself, not as a product.

## License

No license has been chosen yet, which means all rights are reserved and you do not yet have permission to reuse this code. If you want to use it, open an issue and ask.
