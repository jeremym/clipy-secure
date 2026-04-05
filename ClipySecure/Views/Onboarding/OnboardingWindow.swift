import AppKit
import Defaults
import SwiftUI

@MainActor
final class OnboardingWindow {
    private var window: NSWindow?
    private var hostingController: NSHostingController<OnboardingView>?
    private var onComplete: (() -> Void)?
    private var didComplete = false
    private var notificationObserver: Any?

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(onComplete: { [weak self] in
            self?.didComplete = true
            self?.window?.close()
        })

        let controller = NSHostingController(rootView: view)
        hostingController = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "Welcome to ClipySecure")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.contentMaxSize = NSSize(width: 640, height: 480)
        window.center()
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 640, height: 480))
        self.window = window

        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowClose()
            }
        }

        Task {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func handleWindowClose() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        window = nil
        hostingController = nil
        if didComplete {
            onComplete?()
        } else {
            // User closed without completing — start services but show onboarding again next launch
            onComplete?()
            Defaults[.hasCompletedOnboarding] = false
        }
        onComplete = nil
    }
}
