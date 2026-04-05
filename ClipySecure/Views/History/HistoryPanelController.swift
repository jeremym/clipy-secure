import AppKit
import SwiftUI

@MainActor
final class HistoryPanelController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<HistoryListView>?
    private let databaseService: DatabaseService
    private let clipboardMonitor: ClipboardMonitor
    private let pasteService: PasteService

    init(
        databaseService: DatabaseService,
        clipboardMonitor: ClipboardMonitor,
        pasteService: PasteService
    ) {
        self.databaseService = databaseService
        self.clipboardMonitor = clipboardMonitor
        self.pasteService = pasteService
    }

    func togglePanel() {
        if let existing = panel, existing.isVisible {
            existing.close()
            return
        }
        showPanel()
    }

    func showPanel() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = HistoryListView(
            databaseService: databaseService,
            clipboardMonitor: clipboardMonitor,
            pasteService: pasteService,
            onDismiss: { [weak self] in self?.panel?.close() }
        )
        let controller = NSHostingController(rootView: view)
        hostingController = controller

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = String(localized: "Clipboard History")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.center()
        panel.minSize = NSSize(width: 300, height: 300)
        panel.contentViewController = controller
        self.panel = panel

        Task {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
