import AppKit
import Foundation

@MainActor
final class ExcludeAppService {
    private let databaseService: DatabaseService
    private var currentFrontmostBundleId: String?

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
        startObserving()
    }

    private func startObserving() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        currentFrontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    @objc private func appDidActivate(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            currentFrontmostBundleId = app.bundleIdentifier
        }
    }

    func isCurrentAppExcluded() -> Bool {
        guard let bundleId = currentFrontmostBundleId else { return false }
        return (try? databaseService.isAppExcluded(bundleId: bundleId)) ?? false
    }

    func isAppExcluded(bundleId: String) -> Bool {
        (try? databaseService.isAppExcluded(bundleId: bundleId)) ?? false
    }
}
