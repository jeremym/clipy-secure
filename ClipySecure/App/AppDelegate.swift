import Cocoa
import Defaults

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var databaseService: DatabaseService?
    private var clipboardMonitor: ClipboardMonitor?
    private var statusBarController: StatusBarController?
    private var dataCleanupService: DataCleanupService?
    private var snippetEditorWindow: SnippetEditorWindow?
    private var accessibilityService: AccessibilityService?
    private var pasteService: PasteService?
    private var hotKeyService: HotKeyService?
    private var excludeAppService: ExcludeAppService?
    private var preferencesWindow: PreferencesWindow?
    private var historyPanelController: HistoryPanelController?
    private var onboardingWindow: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

            try? cleanup.runCleanup()

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
        if let monitor = clipboardMonitor {
            Task {
                await monitor.stopMonitoring()
            }
        }
    }
}
