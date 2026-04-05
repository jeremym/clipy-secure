import AppKit
import Defaults
import GRDB

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
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
    private var preferencesWindow: PreferencesWindow?

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

    func setPreferencesWindow(_ window: PreferencesWindow) {
        self.preferencesWindow = window
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            if let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "ClipySecure") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
            button.toolTip = "ClipySecure"
        }

        // Defer menu assignment to avoid layout recursion on macOS 26.
        // The status item needs to complete its initial layout pass first.
        Task { [weak self] in
            guard let self else { return }
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
        }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try ClipItem
                .order(Column("updatedAt").desc)
                .limit(500) // Fetch more than needed; menu building trims to settings
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
        statusItem?.button?.performClick(nil)
    }

    func popUpHistoryMenu() {
        menuMode = .historyOnly
        statusItem?.button?.performClick(nil)
    }

    func popUpSnippetMenu() {
        menuMode = .snippetsOnly
        statusItem?.button?.performClick(nil)
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

        if Defaults[.showClearHistoryItem] {
            menu.addItem(NSMenuItem.separator())

            let clearItem = NSMenuItem(
                title: String(localized: "Clear All"),
                action: #selector(clearAllClicked(_:)),
                keyEquivalent: ""
            )
            clearItem.target = self
            menu.addItem(clearItem)
        }

        // Snippet section
        menu.addItem(NSMenuItem.separator())
        addSnippetMenuItems(to: menu)

        menu.addItem(NSMenuItem.separator())

        let editSnippetsItem = NSMenuItem(
            title: String(localized: "Edit Snippets\u{2026}"),
            action: #selector(editSnippetsClicked(_:)),
            keyEquivalent: ""
        )
        editSnippetsItem.target = self
        menu.addItem(editSnippetsItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(
            title: String(localized: "Preferences\u{2026}"),
            action: #selector(preferencesClicked(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    private func buildHistoryMenu(_ menu: NSMenu) {
        addHistoryItems(to: menu)

        if Defaults[.showClearHistoryItem] {
            menu.addItem(NSMenuItem.separator())

            let clearItem = NSMenuItem(
                title: String(localized: "Clear All"),
                action: #selector(clearAllClicked(_:)),
                keyEquivalent: ""
            )
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    private func buildSnippetsMenu(_ menu: NSMenu) {
        addSnippetMenuItems(to: menu)

        if menu.items.isEmpty {
            let emptyItem = NSMenuItem(title: String(localized: "No Snippets"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(NSMenuItem.separator())

        let editSnippetsItem = NSMenuItem(
            title: String(localized: "Edit Snippets\u{2026}"),
            action: #selector(editSnippetsClicked(_:)),
            keyEquivalent: ""
        )
        editSnippetsItem.target = self
        menu.addItem(editSnippetsItem)
    }

    // MARK: - Menu Item Helpers

    private func addHistoryItems(to menu: NSMenu) {
        let maxHistorySize = Defaults[.maxHistorySize]
        let displayItems = Array(historyItems.prefix(maxHistorySize))

        if displayItems.isEmpty {
            let emptyItem = NSMenuItem(title: String(localized: "No History"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        let inlineCount = Defaults[.numberOfItemsInline]
        let folderSize = Defaults[.numberOfItemsInFolder]

        // If inlineCount is 0, show all items inline
        let itemsInline = inlineCount == 0 ? displayItems.count : min(inlineCount, displayItems.count)

        // Add inline items
        for index in 0..<itemsInline {
            let menuItem = buildMenuItem(for: displayItems[index], at: index)
            menu.addItem(menuItem)
        }

        // Add remaining items in numbered folders
        if itemsInline < displayItems.count {
            let remaining = Array(displayItems[itemsInline...])
            let chunks = remaining.chunked(into: folderSize)

            for (chunkIndex, chunk) in chunks.enumerated() {
                let startNum = itemsInline + (chunkIndex * folderSize) + 1
                let endNum = startNum + chunk.count - 1
                let folderTitle = String(localized: "History \(startNum)-\(endNum)")

                let folderItem = NSMenuItem(title: folderTitle, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: folderTitle)

                for (offset, item) in chunk.enumerated() {
                    let globalIndex = itemsInline + (chunkIndex * folderSize) + offset
                    let menuItem = buildMenuItem(for: item, at: globalIndex)
                    submenu.addItem(menuItem)
                }

                folderItem.submenu = submenu
                menu.addItem(folderItem)
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
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let showNumbers = Defaults[.showNumbersInMenu]
        let showImages = Defaults[.showImagesInMenu]
        let showTooltips = Defaults[.showTooltips]
        let tooltipMaxLen = Defaults[.tooltipMaxLength]

        // Truncate title to configured max length
        let displayTitle = String(item.title.prefix(maxLen))

        let keyEquiv: String
        if showNumbers && index < 9 {
            keyEquiv = "\(index + 1)"
        } else {
            keyEquiv = ""
        }

        let menuItem = NSMenuItem(
            title: displayTitle,
            action: #selector(historyItemClicked(_:)),
            keyEquivalent: keyEquiv
        )
        menuItem.target = self
        menuItem.tag = index

        // Show thumbnail for image clips
        if showImages,
           item.primaryType == ClipContentType.tiff.rawValue,
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
                menuItem.title = "\u{1F4DD} " + menuItem.title
            case ClipContentType.pdf.rawValue:
                menuItem.title = "\u{1F4C4} " + menuItem.title
            case ClipContentType.filenames.rawValue:
                menuItem.title = "\u{1F4C1} " + menuItem.title
            case ClipContentType.url.rawValue:
                menuItem.title = "\u{1F517} " + menuItem.title
            case ClipContentType.tiff.rawValue:
                menuItem.title = "\u{1F5BC} " + menuItem.title
            default:
                break
            }
        }

        // Pin indicator
        if item.isPinned {
            menuItem.title = "\u{1F4CC} " + menuItem.title
        }

        // Tooltip
        if showTooltips, let str = item.stringValue {
            menuItem.toolTip = String(str.prefix(tooltipMaxLen))
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

        // Reorder after paste: update the item's timestamp so it moves to top
        if Defaults[.reorderAfterPaste] {
            var updated = item
            updated.updatedAt = Date()
            try? databaseService.save(clip: updated)
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

    @objc private func preferencesClicked(_ sender: NSMenuItem) {
        preferencesWindow?.showWindow()
    }

    @objc private func clearAllClicked(_ sender: NSMenuItem) {
        try? databaseService.deleteAll()
    }
}

// MARK: - Array chunking helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
