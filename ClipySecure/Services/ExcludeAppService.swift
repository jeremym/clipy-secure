import AppKit
import Foundation
import OSLog

@MainActor
final class ExcludeAppService {
    private let databaseService: DatabaseService
    private var currentFrontmostBundleId: String?
    private var previousFrontmostBundleId: String?
    private var lastActivationDate: Date = .distantPast

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
            previousFrontmostBundleId = currentFrontmostBundleId
            currentFrontmostBundleId = app.bundleIdentifier
            lastActivationDate = Date()
        }
    }

    /// Checks whether the copy could have come from an excluded app. The
    /// clipboard poll runs up to `pollWindow` seconds after the copy, so if
    /// the frontmost app changed within that window the previous app may be
    /// the real source — check it too. Skipping a legitimate clip is the
    /// safer failure mode for a privacy feature.
    func isCurrentAppExcluded(pollWindow: TimeInterval = 0) -> Bool {
        if let bundleId = currentFrontmostBundleId, isAppExcluded(bundleId: bundleId) {
            return true
        }
        if Date().timeIntervalSince(lastActivationDate) < pollWindow,
           let previousId = previousFrontmostBundleId,
           isAppExcluded(bundleId: previousId)
        {
            return true
        }
        return false
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
