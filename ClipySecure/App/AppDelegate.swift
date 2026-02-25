import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var databaseService: DatabaseService?
    private var clipboardMonitor: ClipboardMonitor?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let dbService = try DatabaseService()
            databaseService = dbService

            let monitor = ClipboardMonitor(databaseService: dbService)
            clipboardMonitor = monitor

            statusBarController = StatusBarController(
                databaseService: dbService,
                clipboardMonitor: monitor
            )

            Task {
                await monitor.startMonitoring()
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
        if let monitor = clipboardMonitor {
            Task {
                await monitor.stopMonitoring()
            }
        }
    }
}
