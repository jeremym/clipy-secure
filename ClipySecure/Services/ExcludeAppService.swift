import AppKit
import Foundation
import OSLog

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

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            currentFrontmostBundleId = app.bundleIdentifier
        }
    }

    func isCurrentAppExcluded() -> Bool {
        guard let bundleId = currentFrontmostBundleId else { return false }
        do {
            return try databaseService.isAppExcluded(bundleId: bundleId)
        } catch {
            Logger.database.error("Failed to check excluded app: \(error.localizedDescription)")
            return false
        }
    }

    func isAppExcluded(bundleId: String) -> Bool {
        do {
            return try databaseService.isAppExcluded(bundleId: bundleId)
        } catch {
            Logger.database.error("Failed to check excluded app: \(error.localizedDescription)")
            return false
        }
    }
}
