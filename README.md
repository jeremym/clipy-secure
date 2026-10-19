# ClipySecure

A privacy-first clipboard manager for macOS. Everything you copy is stored encrypted on disk, nothing ever leaves your machine, and the searchable index lives only in memory.

**Website:** [jeremym.github.io/clipy-secure](https://jeremym.github.io/clipy-secure/)

An independent, ground-up rewrite of [Clipy](https://github.com/Clipy/Clipy) in Swift 6, rebuilt around one idea: a clipboard manager sees your passwords, tokens, and private messages — so it should be the last app on your Mac storing them in plain text.

![CI](https://github.com/jeremym/clipy-secure/actions/workflows/ci.yml/badge.svg)

## Installing

ClipySecure is signed with its own certificate rather than an Apple Developer ID, and is **not notarized** (see [Verifying a release](#verifying-a-release) and [Why it isn't notarized](#why-it-isnt-notarized)). Pick whichever path you trust.

### Homebrew (recommended)

```bash
brew install --cask jeremym/tap/clipy-secure
open -a ClipySecure
```

The fully-qualified cask name trusts the tap automatically — there is no separate `brew tap` step. The cask removes the quarantine flag on install, so the app launches without a Gatekeeper prompt, and `brew upgrade` keeps the Accessibility permission across updates. There is no in-app updater; updates come through `brew upgrade` only.

### Zip from GitHub Releases

1. Download `ClipySecure-<version>.zip` from the [latest release](https://github.com/jeremym/clipy-secure/releases/latest) and unzip it.
2. Move `ClipySecure.app` to `/Applications`.
3. Because the app is not notarized, the first launch is blocked. Either:
   - Open **System Settings → Privacy & Security**, scroll to *"ClipySecure" was blocked*, click **Open Anyway**, then confirm; or
   - remove the quarantine flag from the Terminal:
     ```bash
     xattr -d com.apple.quarantine /Applications/ClipySecure.app
     ```

You only do this once per downloaded copy.

### Build from source

```bash
git clone https://github.com/jeremym/clipy-secure.git
cd clipy-secure
./scripts/create-signing-cert.sh   # once per machine
./scripts/install-local.sh         # build, sign, install to /Applications, launch
```

`create-signing-cert.sh` generates a self-signed code-signing certificate in your login keychain. It needs no Apple account and no developer membership — it is created and trusted entirely on your own machine. `install-local.sh` then quits any running copy, builds a signed Release, checks the signature actually took, installs to `/Applications`, and launches it. To rebuild after pulling changes, run `install-local.sh` again.

**Why the certificate step exists.** A plain `xcodebuild` signs ad-hoc, producing a designated requirement pinned to the binary's hash. macOS binds the Accessibility grant to that requirement, so **every rebuild looks like a brand new app**: the old grant goes stale, toggling it in System Settings does nothing, and auto-paste breaks. A certificate — even a self-signed one — makes the requirement identity-based, and the grant survives every rebuild. If a stale grant ever does get stuck, clear it once and re-grant:

```bash
tccutil reset Accessibility com.clipysecure.app
```

### Uninstalling

If you installed with Homebrew:

```bash
brew uninstall --cask clipy-secure          # remove the app
brew uninstall --cask --zap clipy-secure    # also delete history, memory, and settings
```

`--zap` trashes `~/Library/Application Support/com.clipysecure.app` and `~/Library/Preferences/com.clipysecure.app.plist`. The AES-GCM key stays in your login Keychain — delete the `ClipySecure` item in Keychain Access to remove it too. Installed from a zip or from source? Drag `ClipySecure.app` to the Trash and remove those two paths plus the Keychain item by hand.

### Requirements

- macOS 14 Sonoma or later
- Accessibility permission, granted on first run, for auto-paste
- Xcode 16 or later, only if building from source

## What it does

- **Clipboard history** in the menu bar — up to 32 items by default, covering text, RTF, RTFD, PDF, images, file paths, and URLs.
- **Single-keystroke paste.** Open the menu and press the digit shown beside a clip to paste it instantly. The most recent clips are `1`, `2`, `3`…; older ones group into numbered folders you open with a digit and paste from with another. No Return, no arrow keys. The key set is configurable (digits by default).
- **Per-row actions.** Hold ⌥ over any menu row to reveal a three-item submenu. On a history row: **Save to Memory** (`m`), **Send to Obsidian** (`o`), **Delete** (`d`). On a memory row: **Promote to Snippet** (`m`), **Send to Obsidian** (`o`), **Forget** (`d`). By keyboard, press ⌥ + the row's key to open its submenu, then `m` / `o` / `d`.
- **Searchable history panel** with live full-text search, and a right-click menu on each result — Paste, Save to Memory (or Forget), Send to Obsidian, Delete.
- **Snippets** — reusable text organised in folders, importable and exportable as XML. A few example snippets are added on first run to show how the app works; delete them whenever.
- **Memory** — a parking lot between history and snippets. Keep the clips you want to hold onto; by default they never expire, but you can set an optional expiry (in days), and the most recent are kept up to a configurable cap. The whole section can be hidden if you don't use it.
- **Obsidian export** — send any clip to a chosen Obsidian vault as a Markdown note, with optional YAML frontmatter and a code fence for non-Markdown. Local file write only; Obsidian doesn't need to be running.
- **App exclusion** — name the apps whose clipboard content should never be recorded, such as a password manager.
- Respects the system *concealed* pasteboard flag, so well-behaved password managers are ignored automatically.

The tiers form a ladder: **History** (everything you copy, expiring on its own) → **Memory** (clips you choose to keep) → **Snippets** (curated, reusable text) or **Obsidian** (filed into your vault). [How it works →](https://jeremym.github.io/clipy-secure/how-it-works/)

## How the privacy works

- **Encrypted at rest.** Clip content — titles, text, RTF, PDF, images, filenames, URLs — is encrypted field-by-field with AES-GCM via CryptoKit before it touches SQLite. The key lives in your Keychain. Plaintext exists only in memory, and the model type cannot persist it even by accident.
- **Keyed content hashes.** Duplicate detection uses HMAC rather than a plain hash, so the database cannot be scanned for known values.
- **The search index never hits disk.** The FTS5 index is built in an attached in-memory database and rebuilt at launch from decrypted rows, so searchable plaintext has nowhere to leak to.
- **No network features.** The app contains no telemetry, sync, update check, or other networking feature.
- **Not sandboxed, deliberately.** Auto-paste posts a synthetic ⌘V through CGEvent, which is exactly the cross-application control App Sandbox exists to prevent — a sandboxed build never appears under Accessibility at all. Privacy here comes from encryption, not from the sandbox. This is also why upstream Clipy is not on the Mac App Store.

**Two deliberate exceptions.** Both move content out of the encrypted store only by your explicit action, never automatically, and never over a network:

- **Snippets** are stored in plain text. They are content you wrote and curate yourself, and they export as plaintext XML by design.
- **Obsidian export** writes a clip into your vault as a plain Markdown file when you choose *Send to Obsidian*.

Don't keep secrets in either. Everything else — all of clipboard history and Memory — stays encrypted at rest.

## Verifying a release

Each release ships `ClipySecure-<version>.zip` alongside a `.sha256` file. Confirm the download:

```bash
shasum -a 256 ClipySecure-1.0.0.zip
# compare against the published .sha256, e.g.:
# 0e47c7c99732c8541eb2eb61e3f6307f4cbcfda4a5a1b404c6c4118912adca9f
```

Confirm the signature on the installed app. Because it is signed with the project's own certificate, the designated requirement is identity-based and stable across releases:

```bash
codesign -d -r- /Applications/ClipySecure.app
# designated => identifier "com.clipysecure.app" and certificate leaf = H"a3ed032a6666d06c91d1c35147ad0e44093c1b5e"
```

If the output pins a `cdhash` instead, you have an ad-hoc build, not a release.

## Why it isn't notarized

Notarization requires a paid Apple Developer ID, which this project does not have. The app is instead signed with a long-lived self-signed certificate. That is enough for macOS to keep the Accessibility grant stable across updates (the grant is bound to the certificate's leaf hash, a value you can check yourself above), but it is **not** an Apple notarization and should not be mistaken for one. Gatekeeper will warn on a fresh download; the Homebrew cask clears the quarantine flag for you, and the zip path documents the one-time "Open Anyway" step above. Integrity rests on the published sha256 and the certificate leaf hash, both verifiable with the commands above.

## Default shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘V | Clip menu at the pointer — history, snippets, and memory |
| ⌃⌘V | Clipboard history search |

Both are rebindable in Preferences, along with an optional "Clear History" shortcut.

## Building and testing

```bash
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' build
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' test
```

The test suite runs against an in-memory database with an ephemeral key, so it never touches your Keychain or your real history. It covers CRUD, full-text search, hash stability, snippets, app exclusion, import deduplication, encryption at rest, the encryption migration, and regressions from past security fixes.

## Architecture

Swift 6 with strict concurrency. An AppKit shell — status item, windows, menus — hosting SwiftUI views through `NSHostingController`. Clipboard monitoring is an actor polling the pasteboard every 500ms. Storage is GRDB over SQLite, with GRDB `ValueObservation` driving live menu updates; observations deliberately select only lightweight columns, leaving image and document blobs to be fetched on demand at paste time.

Dependencies are Swift Package Manager only: GRDB.swift, KeyboardShortcuts, Defaults, and LaunchAtLogin-Modern.

## License

MIT — see [LICENSE](LICENSE). Upstream [Clipy](https://github.com/Clipy/Clipy), which this rewrite follows in spirit, is MIT licensed too.
