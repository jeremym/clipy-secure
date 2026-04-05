import AppKit
import SwiftUI

@MainActor
final class SnippetEditorWindow {
    private var window: NSWindow?
    private var hostingController: NSHostingController<SnippetEditorView>?
    private let viewModel: SnippetEditorViewModel

    init(viewModel: SnippetEditorViewModel) {
        self.viewModel = viewModel
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
        window.center()
        window.minSize = NSSize(width: 600, height: 450)
        window.contentViewController = controller
        self.window = window

        // Defer display to next run loop tick to avoid layout recursion on macOS 26.
        // Setting contentViewController triggers SwiftUI layout; showing the window
        // in the same tick triggers a second pass, causing recursion.
        Task {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func close() {
        window?.close()
        window = nil
        hostingController = nil
    }
}
