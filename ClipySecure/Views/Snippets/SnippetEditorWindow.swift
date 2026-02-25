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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.title = "Snippet Editor"
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 500, height: 350)
        window.contentViewController = controller

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
        hostingController = nil
    }
}
