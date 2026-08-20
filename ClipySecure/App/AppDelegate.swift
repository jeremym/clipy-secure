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

            let cleanup = DataCleanupService(dbQueue: dbService.dbQueue)
            dataCleanupService = cleanup

            do {
                try cleanup.runCleanup()
            } catch {
                Logger.database.error("Startup cleanup failed: \(error.localizedDescription)")
            }

            // Menu bar apps run for weeks — expiration must be enforced
            // periodically, not just at launch.
            cleanupTask = Task { [cleanup] in
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
            let alert = NSAlert()
            alert.messageText = String(localized: "Failed to Initialize")
            alert.informativeText = String(localized: "ClipySecure could not start: \(error.localizedDescription)")
            alert.alertStyle = .critical
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
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
