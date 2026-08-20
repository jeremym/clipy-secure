import AppKit
import SwiftUI

@MainActor
final class SnippetEditorWindow {
    private var window: NSWindow?
    private var hostingController: NSHostingController<SnippetEditorView>?
    private var notificationObserver: Any?
    private let viewModel: SnippetEditorViewModel

    init(viewModel: SnippetEditorViewModel) {
        self.viewModel = viewModel
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        ActivationPolicyManager.beginWindowSession()

        let controller = NSHostingController(rootView: SnippetEditorView(viewModel: viewModel))
        hostingController = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "Snippet Editor")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 450)
        window.setCenteredContent(controller, size: NSSize(width: 900, height: 650))
        self.window = window

        // The user can close this with the red button, which bypasses close();
        // without observing that the app would never drop back to .accessory.
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowClose()
            }
        }

        window.presentDeferred()
    }

    func close() {
        window?.close()
    }

    private func handleWindowClose() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        window = nil
        hostingController = nil
        ActivationPolicyManager.endWindowSession()
    }
}
