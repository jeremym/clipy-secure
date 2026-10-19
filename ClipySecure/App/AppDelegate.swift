import Cocoa
import Defaults
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var databaseService: DatabaseService?
    private var clipboardMonitor: ClipboardMonitor?
    private var statusBarController: StatusBarController?
    private var dataCleanupService: DataCleanupService?
    private var cleanupTask: Task<Void, Never>?
    private var snippetEditorWindow: SnippetEditorWindow?
    private var accessibilityService: AccessibilityService?
    private var pasteService: PasteService?
    private var hotKeyService: HotKeyService?
    private var excludeAppService: ExcludeAppService?
    private var preferencesWindow: PreferencesWindow?
    private var historyPanelController: HistoryPanelController?
    private var onboardingWindow: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must precede any window: supplies Cmd-Q and the standard editing key
        // equivalents, which AppKit routes through the main menu.
        MainMenu.install()

        if Defaults[.hasCompletedOnboarding] {
            startServices()
        } else {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        let onboarding = OnboardingWindow(onComplete: { [weak self] in
            Defaults[.hasCompletedOnboarding] = true
            self?.onboardingWindow = nil
            self?.startServices()
        })
        onboardingWindow = onboarding
        onboarding.showWindow()
    }

    private func startServices() {
        do {
            let dbService = try DatabaseService()
            databaseService = dbService

            // First-run only: drop a few example snippets in. No-op afterward.
            SeedService.seedExampleSnippetsIfNeeded(into: dbService)

            let cleanup = DataCleanupService(dbQueue: dbService.dbQueue)
            dataCleanupService = cleanup

            do {
                try cleanup.runCleanup()
            } catch {
                Logger.database.error("Startup cleanup failed: \(error.localizedDescription)")
            }

            // Menu bar apps run for weeks — expiration must be enforced
            // periodically, not just at launch. Detached so the delete + VACUUM
            // runs off the main actor (DataCleanupService is Sendable and only
            // touches the thread-safe dbQueue); otherwise a Task here inherits
            // @MainActor and VACUUM stalls the UI (review #10).
            cleanupTask = Task.detached { [cleanup] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(Constants.cleanupIntervalSeconds))
                    } catch {
                        return // cancelled
                    }
                    do {
                        try cleanup.runCleanup()
                    } catch {
                        Logger.database.error("Periodic cleanup failed: \(error.localizedDescription)")
                    }
                }
            }

            let excludeService = ExcludeAppService(databaseService: dbService)
            excludeAppService = excludeService

            let monitor = ClipboardMonitor(
                databaseService: dbService,
                excludeAppService: excludeService,
                dataCleanupService: cleanup
            )
            clipboardMonitor = monitor

            let accessibility = AccessibilityService()
            accessibilityService = accessibility

            let paste = PasteService(accessibilityService: accessibility)
            pasteService = paste

            let statusBar = StatusBarController(
                databaseService: dbService,
                clipboardMonitor: monitor,
                pasteService: paste,
                accessibilityService: accessibility
            )
            statusBarController = statusBar

            let snippetVM = SnippetEditorViewModel(databaseService: dbService)
            let editorWindow = SnippetEditorWindow(viewModel: snippetVM)
            snippetEditorWindow = editorWindow
            statusBar.setSnippetEditorWindow(editorWindow)

            let prefs = PreferencesWindow(databaseService: dbService)
            preferencesWindow = prefs
            statusBar.setPreferencesWindow(prefs)

            let historyPanel = HistoryPanelController(
                databaseService: dbService,
                clipboardMonitor: monitor,
                pasteService: paste
            )
            historyPanelController = historyPanel

            let hotKeys = HotKeyService(
                statusBarController: statusBar,
                databaseService: dbService,
                historyPanelController: historyPanel
            )
            hotKeyService = hotKeys

            Task {
                await monitor.startMonitoring()
            }

        } catch {
            handleStartupFailure(error)
        }
    }

    /// Recovery for a failed start — most often the Keychain prompt being denied
    /// after a re-sign, which leaves the encryption key unreadable. Rather than
    /// just terminating (review #15), offer to retry (re-prompt) or reset the
    /// store (new key + empty history). Quit stays the safe default button.
    private func handleStartupFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "ClipySecure Couldn't Start")
        alert.informativeText = String(localized: """
            \(error.localizedDescription)

            This usually means access to the encryption key in your Keychain was \
            denied. You can try again, or reset to start fresh (this erases saved \
            history and creates a new key).
            """)
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "Try Again"))
        alert.addButton(withTitle: String(localized: "Reset History\u{2026}"))
        alert.addButton(withTitle: String(localized: "Quit"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            startServices()
        case .alertSecondButtonReturn:
            confirmResetAndRestart(originalError: error)
        default:
            NSApplication.shared.terminate(nil)
        }
    }

    private func confirmResetAndRestart(originalError: Error) {
        let confirm = NSAlert()
        confirm.messageText = String(localized: "Reset ClipySecure?")
        confirm.informativeText = String(localized: "This permanently deletes your saved clipboard history and encryption key, then starts fresh. This can't be undone.")
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: String(localized: "Reset"))
        confirm.addButton(withTitle: String(localized: "Cancel"))
        confirm.buttons[0].hasDestructiveAction = true
        confirm.buttons[0].keyEquivalent = ""
        confirm.buttons[1].keyEquivalent = "\r"

        guard confirm.runModal() == .alertFirstButtonReturn else {
            handleStartupFailure(originalError)
            return
        }
        do {
            try DatabaseService.destroyStore()
        } catch {
            Logger.database.error("Store reset failed: \(error.localizedDescription)")
        }
        startServices()
    }

    /// Target of the main-menu "Preferences…" item (⌘,), reached through the
    /// responder chain. No-op until services are up (e.g. during onboarding),
    /// since the window is created in `startServices()`.
    @objc func openPreferences(_ sender: Any?) {
        preferencesWindow?.showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupTask?.cancel()

        // Best effort, never blocking. The previous version created a Task and
        // waited on a DispatchSemaphore for it — a guaranteed deadlock: this
        // class is @MainActor, so `Task {}` inherited main-actor isolation and
        // could not start while the main thread sat in semaphore.wait(). Quit
        // from the status bar menu hung the app permanently.
        //
        // There is also nothing to wait for. stopMonitoring() only cancels the
        // polling task; every clip is committed by its own GRDB write as it is
        // captured, so process exit cannot lose or corrupt data. `Task.detached`
        // avoids inheriting the main actor so it can run if the run loop turns
        // once more before exit, and is harmless if it doesn't.
        if let monitor = clipboardMonitor {
            Task.detached { await monitor.stopMonitoring() }
        }
    }
}
