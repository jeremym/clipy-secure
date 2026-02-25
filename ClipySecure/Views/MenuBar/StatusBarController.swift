import AppKit
import GRDB

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let databaseService: DatabaseService
    private let clipboardMonitor: ClipboardMonitor
    private var historyItems: [ClipItem] = []
    private var observationTask: Task<Void, Never>?

    init(databaseService: DatabaseService, clipboardMonitor: ClipboardMonitor) {
        self.databaseService = databaseService
        self.clipboardMonitor = clipboardMonitor
        super.init()
        setupStatusBar()
        startObservation()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "ClipySecure") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
            button.toolTip = "ClipySecure"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try ClipItem
                .order(Column("updatedAt").desc)
                .limit(Constants.defaultHistoryLimit)
                .fetchAll(db)
        }

        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await items in observation.values(in: self.databaseService.dbQueue) {
                    self.historyItems = items
                }
            } catch {
                // Observation ended
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if historyItems.isEmpty {
            let emptyItem = NSMenuItem(title: "No History", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, item) in historyItems.enumerated() {
                let menuItem = NSMenuItem(
                    title: item.title,
                    action: #selector(historyItemClicked(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                menuItem.target = self
                menuItem.tag = index
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(
            title: "Clear All",
            action: #selector(clearAllClicked(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    // MARK: - Actions

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < historyItems.count,
              let stringValue = historyItems[index].stringValue else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(stringValue, forType: .string)
        let changeCount = pasteboard.changeCount

        Task {
            await clipboardMonitor.updateLastSetChangeCount(changeCount)
        }
    }

    @objc private func clearAllClicked(_ sender: NSMenuItem) {
        try? databaseService.deleteAll()
    }
}
