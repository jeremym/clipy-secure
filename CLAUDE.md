# ClipySecure

Privacy-first clipboard manager for macOS. Full rewrite of [Clipy](https://github.com/Clipy/Clipy).

## Quick Reference

- **Language:** Swift 6.x with strict concurrency
- **Target:** macOS 14+ (Sonoma)
- **UI:** AppKit shell (NSStatusItem/NSWindow) + SwiftUI views via NSHostingController
- **Database:** GRDB.swift (SQLite) — encryption deferred, see `.context/security-hardening-plan.md`
- **Dependencies (SPM only):** GRDB.swift, KeyboardShortcuts, Defaults, LaunchAtLogin-Modern
- **Branch:** `jeremym/clipy-secure-rebuild`
- **Target branch for PRs:** `develop`

## Build & Test

```bash
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' build
xcodebuild -project ClipySecure.xcodeproj -scheme ClipySecure -destination 'platform=macOS' test
```

Tests use an in-memory database (`DatabaseService(dbQueue:)` initializer). 17 unit tests covering DB CRUD, FTS search, hash stability, pinned/memory preservation, snippets, excluded apps.

## Architecture

- **App entry:** `main.swift` (NOT `@main` — broken on macOS 26 Tahoe)
- **Services are wired in** `AppDelegate.applicationDidFinishLaunching`
- **Clipboard monitoring:** Actor-based polling (500ms) via `ClipboardMonitor`
- **Menu:** `StatusBarController` builds NSMenu in `menuNeedsUpdate` using a `MenuMode` enum
- **Paste:** `PasteService` writes to NSPasteboard then simulates Cmd+V via CGEvent
- **Observations:** GRDB `ValueObservation` for live updates; observations fetch lightweight columns only (no blobs)
- **Logging:** `os.log` Logger via `Logger+App.swift` (subsystem: `com.clipysecure.app`)

## Key Patterns

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
- Do not add network entitlements — app is intentionally offline (no telemetry)

## Project Status

All features complete (Phases 0-8). Code review complete with P0-P3 fixes applied.

**One major item deferred:** Database encryption. See `.context/security-hardening-plan.md` for options (CryptoKit AES-GCM field-level or SQLCipher via GRDB package traits). Previous attempts introduced too many errors.

## Detailed Context

- **Full plan:** `.context/PLAN.md`
- **Code review results:** `.context/review-summary.md` and `review-chunk-{1-6}-*.md`
- **Security hardening status:** `.context/security-hardening-plan.md`
