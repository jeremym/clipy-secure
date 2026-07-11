# ClipySecure

Privacy-first clipboard manager for macOS. Full rewrite of [Clipy](https://github.com/Clipy/Clipy).

## Quick Reference

- **Language:** Swift 6.x with strict concurrency
- **Target:** macOS 14+ (Sonoma)
- **UI:** AppKit shell (NSStatusItem/NSWindow) + SwiftUI views via NSHostingController
- **Database:** GRDB.swift (SQLite) with field-level AES-GCM encryption (CryptoKit); key in Keychain via `EncryptionKeyManager`
- **Dependencies (SPM only):** GRDB.swift, KeyboardShortcuts, Defaults, LaunchAtLogin-Modern
- **Branch:** `jeremym/clipy-secure-rebuild`
- **Target branch for PRs:** `develop`

## Build & Test

```bash
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' build
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' test
```

Tests use an in-memory database (`DatabaseService(dbQueue:)` initializer) with an ephemeral encryption key — no Keychain access. 33 unit tests covering DB CRUD, FTS search, hash stability, pinned/memory preservation, snippets, excluded apps, import deduplication, encryption at rest, the v10 encryption migration, and security-fix regressions (transient pasteboard, duplicate handling, cleanup counts).

## Architecture

- **App entry:** `main.swift` (NOT `@main` — broken on macOS 26 Tahoe)
- **Services are wired in** `AppDelegate.applicationDidFinishLaunching`
- **Clipboard monitoring:** Actor-based polling (500ms) via `ClipboardMonitor`
- **Menu:** `StatusBarController` coordinates menu via `MenuMode` enum; `ClipMenuBuilder` handles all NSMenuItem construction
- **Paste:** `PasteService` writes to NSPasteboard then simulates Cmd+V via CGEvent
- **Observations:** GRDB `ValueObservation` for live updates; observations fetch lightweight columns only (no blobs)
- **Logging:** `os.log` Logger via `Logger+App.swift` (subsystem: `com.clipysecure.app`)

## Key Patterns

- **Encryption:** Clip content (title, text, RTF, PDF, image, filenames, URLs) is AES-GCM encrypted into `enc*` blob columns via `FieldEncryption`; the plaintext fields on `ClipItem` are in-memory only (excluded from `CodingKeys`, so GRDB cannot persist them). `contentHash` is stored HMAC-keyed. All writes go through `DatabaseService.save`; readers call `databaseService.decrypt(_:)` on fetched/observed rows. Reordering uses `touch(clipId:)`, never `save` (lightweight observed rows lack blobs).
- **Search:** FTS5 index lives in an attached in-memory database (`ftsmem`), rebuilt at launch from decrypted rows — searchable plaintext never reaches disk. Works because `DatabaseQueue` is a single connection.
- **Error handling:** Use `do/catch` + `Logger.error()`, NOT `try?`. Silent error swallowing was a major code review finding.
- **GRDB observations:** Select only metadata columns. Fetch full blobs on demand (paste time), not in observation queries.
- **SwiftUI in AppKit:** Always use `NSHostingController` + `contentViewController`. Defer `makeKeyAndOrderFront` via `Task { }` on macOS 26 to avoid layout recursion.
- **FTS5:** Standalone table with `clipId UNINDEXED` join column — NOT content-synced (broken with GRDB text PKs).
- **Image thumbnails:** CGContext-based drawing (NOT `lockFocus`/`unlockFocus` — deprecated).
- **Preferences window:** NSToolbar with `.preference` style, NOT SwiftUI TabView.

## What NOT to Do

- Do not use `@main` on AppDelegate (broken on macOS 26)
- Do not use `NSLog` for debugging (invisible in `log stream` on macOS 26)
- Do not use `try?` for database operations — always log errors
- Do not fetch blob columns (imageData, rtfData, pdfData) in observation queries
- Do not use content-synced FTS5 tables with GRDB
- Do not add `lockFocus`/`unlockFocus` calls (deprecated, not thread-safe)
- Do not add plaintext content columns to `clipItem` or write clip content to disk unencrypted — content goes in `enc*` columns only
- Do not add network entitlements — app is intentionally offline (no telemetry)
- Do not use `NSApp.activate(ignoringOtherApps:)` — deprecated in macOS 14; use `NSApp.activate()` instead

## Project Status

All features complete (Phases 0-8). Code review complete — all P0-P3 fixes plus additional code quality work (import deduplication, StatusBarController breakup, deprecated API cleanup) applied.

Database encryption complete: field-level AES-GCM on all clip content, keyed content hashes, in-memory FTS index, v10 migration (encrypts existing rows, drops plaintext columns, VACUUMs to scrub old pages). Snippets remain plaintext by design (user-curated, exported as plaintext XML). SQLCipher via GRDB package traits remains a future option for full-file encryption.

## Detailed Context

- **Full plan:** `.context/PLAN.md`
- **Code review results:** `.context/review-summary.md` and `review-chunk-{1-6}-*.md`
- **Security hardening status:** `.context/security-hardening-plan.md`
