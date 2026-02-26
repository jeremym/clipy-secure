import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var databaseService: DatabaseService?
    private var clipboardMonitor: ClipboardMonitor?
    private var statusBarController: StatusBarController?
    private var dataCleanupService: DataCleanupService?
    private var cleanupTimer: Timer?
    private var snippetEditorWindow: SnippetEditorWindow?
    private var accessibilityService: AccessibilityService?
    private var pasteService: PasteService?
    private var hotKeyService: HotKeyService?
    private var excludeAppService: ExcludeAppService?
    private var preferencesWindow: PreferencesWindow?
    private var historyPanelController: HistoryPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let dbService = try DatabaseService()
            databaseService = dbService

            let cleanup = DataCleanupService(dbQueue: dbService.dbQueue)
            dataCleanupService = cleanup

            // Run cleanup on launch
            try? cleanup.runCleanup()

            // Set up app exclusion service
            let excludeService = ExcludeAppService(databaseService: dbService)
            excludeAppService = excludeService

            let monitor = ClipboardMonitor(
                databaseService: dbService,
                excludeAppService: excludeService
            )
            clipboardMonitor = monitor

            // Set up accessibility and paste services
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

            // Set up snippet editor
            let snippetVM = SnippetEditorViewModel(databaseService: dbService)
            let editorWindow = SnippetEditorWindow(viewModel: snippetVM)
            snippetEditorWindow = editorWindow
            statusBar.setSnippetEditorWindow(editorWindow)

            // Set up preferences window
            let prefs = PreferencesWindow(databaseService: dbService)
            preferencesWindow = prefs
            statusBar.setPreferencesWindow(prefs)

            // Set up history panel
            let historyPanel = HistoryPanelController(
                databaseService: dbService,
                clipboardMonitor: monitor,
                pasteService: paste
            )
            historyPanelController = historyPanel

            // Set up global hotkeys
            let hotKeys = HotKeyService(
                statusBarController: statusBar,
                databaseService: dbService,
                historyPanelController: historyPanel
            )
            hotKeyService = hotKeys

            Task {
                await monitor.startMonitoring()
            }

            // Schedule periodic cleanup every 30 minutes
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak cleanup] _ in
                try? cleanup?.runCleanup()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Initialize"
            alert.informativeText = "ClipySecure could not start: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupTimer?.invalidate()
        cleanupTimer = nil

        if let monitor = clipboardMonitor {
            Task {
                await monitor.stopMonitoring()
            }
        }
    }
}
