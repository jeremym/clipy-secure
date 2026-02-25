import AppKit
import GRDB

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let databaseService: DatabaseService
    private let clipboardMonitor: ClipboardMonitor
    private let pasteService: PasteService
    private let accessibilityService: AccessibilityService
    private var historyItems: [ClipItem] = []
    private var snippetFolders: [SnippetFolder] = []
    private var allSnippets: [Snippet] = []
    private var observationTask: Task<Void, Never>?
    private var snippetObservationTask: Task<Void, Never>?
    private var snippetEditorWindow: SnippetEditorWindow?

    private enum MenuMode {
        case full
        case historyOnly
        case snippetsOnly
    }
    private var menuMode: MenuMode = .full

    init(
        databaseService: DatabaseService,
        clipboardMonitor: ClipboardMonitor,
        pasteService: PasteService,
        accessibilityService: AccessibilityService
    ) {
        self.databaseService = databaseService
        self.clipboardMonitor = clipboardMonitor
        self.pasteService = pasteService
        self.accessibilityService = accessibilityService
        super.init()
        setupStatusBar()
        startObservation()
        startSnippetObservation()
    }

    func setSnippetEditorWindow(_ window: SnippetEditorWindow) {
        self.snippetEditorWindow = window
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

    private func startSnippetObservation() {
        let observation = ValueObservation.tracking { db -> ([SnippetFolder], [Snippet]) in
            let folders = try SnippetFolder
                .order(Column("sortIndex").asc)
                .fetchAll(db)
            let snippets = try Snippet
                .order(Column("sortIndex").asc)
                .fetchAll(db)
            return (folders, snippets)
        }

        snippetObservationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await (folders, snippets) in observation.values(in: self.databaseService.dbQueue) {
                    self.snippetFolders = folders
                    self.allSnippets = snippets
                }
            } catch {
                // Observation ended
            }
        }
    }

    deinit {
        observationTask?.cancel()
        snippetObservationTask?.cancel()
    }

    // MARK: - Hotkey Menu Actions

    func popUpMainMenu() {
        menuMode = .full
        statusItem.button?.performClick(nil)
    }

    func popUpHistoryMenu() {
        menuMode = .historyOnly
        statusItem.button?.performClick(nil)
    }

    func popUpSnippetMenu() {
        menuMode = .snippetsOnly
        statusItem.button?.performClick(nil)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let currentMode = menuMode
        menuMode = .full

        switch currentMode {
        case .full:
            buildFullMenu(menu)
        case .historyOnly:
            buildHistoryMenu(menu)
        case .snippetsOnly:
            buildSnippetsMenu(menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuMode = .full
    }

    // MARK: - Menu Builders

    private func buildFullMenu(_ menu: NSMenu) {
        addHistoryItems(to: menu)

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(
            title: "Clear All",
            action: #selector(clearAllClicked(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        // Snippet section
        menu.addItem(NSMenuItem.separator())
        addSnippetMenuItems(to: menu)

        menu.addItem(NSMenuItem.separator())

        let editSnippetsItem = NSMenuItem(
            title: "Edit Snippets\u{2026}",
            action: #selector(editSnippetsClicked(_:)),
            keyEquivalent: ""
        )
        editSnippetsItem.target = self
        menu.addItem(editSnippetsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    private func buildHistoryMenu(_ menu: NSMenu) {
        addHistoryItems(to: menu)

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(
            title: "Clear All",
            action: #selector(clearAllClicked(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
    }

    private func buildSnippetsMenu(_ menu: NSMenu) {
        addSnippetMenuItems(to: menu)

        if menu.items.isEmpty {
            let emptyItem = NSMenuItem(title: "No Snippets", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(NSMenuItem.separator())

        let editSnippetsItem = NSMenuItem(
            title: "Edit Snippets\u{2026}",
            action: #selector(editSnippetsClicked(_:)),
            keyEquivalent: ""
        )
        editSnippetsItem.target = self
        menu.addItem(editSnippetsItem)
    }

    // MARK: - Menu Item Helpers

    private func addHistoryItems(to menu: NSMenu) {
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
    }

    private func addSnippetMenuItems(to menu: NSMenu) {
        let enabledFolders = snippetFolders.filter(\.isEnabled)
        guard !enabledFolders.isEmpty else { return }

        for folder in enabledFolders {
            let folderSnippets = allSnippets.filter { $0.folderId == folder.id && $0.isEnabled }
            guard !folderSnippets.isEmpty else { continue }

            let folderItem = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: folder.title)

            for snippet in folderSnippets {
                let snippetItem = NSMenuItem(
                    title: snippet.title,
                    action: #selector(snippetClicked(_:)),
                    keyEquivalent: ""
                )
                snippetItem.target = self
                snippetItem.representedObject = snippet.content
                submenu.addItem(snippetItem)
            }

            folderItem.submenu = submenu
            menu.addItem(folderItem)
        }
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

        // Auto-paste with delay to let menu dismiss and target app regain focus
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
    }

    @objc private func snippetClicked(_ sender: NSMenuItem) {
        guard let content = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        let changeCount = pasteboard.changeCount
        Task {
            await clipboardMonitor.updateLastSetChangeCount(changeCount)
        }

        // Auto-paste with delay to let menu dismiss and target app regain focus
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
    }

    @objc private func editSnippetsClicked(_ sender: NSMenuItem) {
        snippetEditorWindow?.showWindow()
    }

    @objc private func clearAllClicked(_ sender: NSMenuItem) {
        try? databaseService.deleteAll()
    }
}
