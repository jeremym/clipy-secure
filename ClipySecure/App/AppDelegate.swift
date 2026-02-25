import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var databaseService: DatabaseService?
    private var clipboardMonitor: ClipboardMonitor?
    private var statusBarController: StatusBarController?
    private var dataCleanupService: DataCleanupService?
    private var cleanupTimer: Timer?
    private var snippetEditorWindow: SnippetEditorWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let dbService = try DatabaseService()
            databaseService = dbService

            let cleanup = DataCleanupService(dbQueue: dbService.dbQueue)
            dataCleanupService = cleanup

            // Run cleanup on launch
            try? cleanup.runCleanup()

            let monitor = ClipboardMonitor(databaseService: dbService)
            clipboardMonitor = monitor

            let statusBar = StatusBarController(
                databaseService: dbService,
                clipboardMonitor: monitor
            )
            statusBarController = statusBar

            // Set up snippet editor
            let snippetVM = SnippetEditorViewModel(databaseService: dbService)
            let editorWindow = SnippetEditorWindow(viewModel: snippetVM)
            snippetEditorWindow = editorWindow
            statusBar.setSnippetEditorWindow(editorWindow)

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
