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
                let menuItem = buildMenuItem(for: item, at: index)
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

    // MARK: - Menu Item Builder

    private func buildMenuItem(for item: ClipItem, at index: Int) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: item.title,
            action: #selector(historyItemClicked(_:)),
            keyEquivalent: index < 9 ? "\(index + 1)" : ""
        )
        menuItem.target = self
        menuItem.tag = index

        // Show thumbnail for image clips
        if item.primaryType == ClipContentType.tiff.rawValue,
           let data = item.imageData,
           let image = NSImage(data: data)
        {
            image.size = NSSize(width: 32, height: 32)
            menuItem.image = image
        }

        // Add type indicator for non-text clips
        if let typeStr = item.primaryType as String? {
            switch typeStr {
            case ClipContentType.rtf.rawValue, ClipContentType.rtfd.rawValue:
                menuItem.title = "\u{1F4DD} " + item.title
            case ClipContentType.pdf.rawValue:
                menuItem.title = "\u{1F4C4} " + item.title
            case ClipContentType.filenames.rawValue:
                menuItem.title = "\u{1F4C1} " + item.title
            case ClipContentType.url.rawValue:
                menuItem.title = "\u{1F517} " + item.title
            case ClipContentType.tiff.rawValue:
                menuItem.title = "\u{1F5BC} " + item.title
            default:
                break
            }
        }

        // Pin indicator
        if item.isPinned {
            menuItem.title = "\u{1F4CC} " + menuItem.title
        }

        return menuItem
    }

    // MARK: - Actions

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < historyItems.count else { return }

        let item = historyItems[index]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Restore all available types when pasting
        var wroteContent = false

        if let rtfData = item.rtfData {
            pasteboard.setData(rtfData, forType: .rtf)
            wroteContent = true
        }
        if let pdfData = item.pdfData {
            pasteboard.setData(pdfData, forType: .pdf)
            wroteContent = true
        }
        if let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .png)
            wroteContent = true
        }
        if let filenamesStr = item.filenames,
           let data = filenamesStr.data(using: .utf8),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            let urls = paths.compactMap { URL(fileURLWithPath: $0) as NSURL }
            pasteboard.writeObjects(urls)
            wroteContent = true
        }
        if let stringValue = item.stringValue {
            pasteboard.setString(stringValue, forType: .string)
            wroteContent = true
        }

        guard wroteContent else { return }
        let changeCount = pasteboard.changeCount

        Task {
            await clipboardMonitor.updateLastSetChangeCount(changeCount)
        }
    }

    @objc private func clearAllClicked(_ sender: NSMenuItem) {
        try? databaseService.deleteAll()
    }
}
