import AppKit
import SwiftUI

@MainActor
final class SnippetEditorWindow {
    private var panel: NSPanel?
    private let viewModel: SnippetEditorViewModel

    init(viewModel: SnippetEditorViewModel) {
        self.viewModel = viewModel
    }

    func showWindow() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Snippet Editor"
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.minSize = NSSize(width: 500, height: 350)

        let hostingView = NSHostingView(rootView: SnippetEditorView(viewModel: viewModel))
        panel.contentView = hostingView

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
