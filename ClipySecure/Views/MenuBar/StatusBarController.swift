import AppKit
import Defaults
import GRDB
import OSLog
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let databaseService: DatabaseService
    private let clipboardMonitor: ClipboardMonitor
    private let pasteService: PasteService
    private let accessibilityService: AccessibilityService
    private var historyItems: [ClipItem] = []
    private var memoryItems: [ClipItem] = []
    private var snippetFolders: [SnippetFolder] = []
    private var allSnippets: [Snippet] = []
    private var observationTask: Task<Void, Never>?
    private var memoryObservationTask: Task<Void, Never>?
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
        startMemoryObservation()
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

    // MARK: - Observations

    private func startObservation() {
        // History shows ALL items (including memory) ordered by copy date.
        // Select only lightweight columns — blobs are fetched on demand at paste time.
        let cols = DatabaseService.lightweightColumns
        let observation = ValueObservation.tracking { db in
            try ClipItem
                .select(cols)
                .order(Column("updatedAt").desc)
                .limit(500)
                .fetchAll(db)
        }

        let dbQueue = databaseService.dbQueue
        observationTask = Task { [weak self] in
            do {
                for try await items in observation.values(in: dbQueue) {
                    guard let self else { return }
                    self.historyItems = items
                }
            } catch {
                // Observation ended
            }
        }
    }

    private func startMemoryObservation() {
        // Memory shows only isMemory items, ordered by memorizedAt (save date).
        let cols = DatabaseService.lightweightColumns
        let observation = ValueObservation.tracking { db in
            try ClipItem
                .select(cols)
                .filter(Column("isMemory") == true)
                .order(Column("memorizedAt").desc)
                .limit(500)
                .fetchAll(db)
        }

        let dbQueue = databaseService.dbQueue
        memoryObservationTask = Task { [weak self] in
            do {
                for try await items in observation.values(in: dbQueue) {
                    guard let self else { return }
                    self.memoryItems = items
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

        let dbQueue = databaseService.dbQueue
        snippetObservationTask = Task { [weak self] in
            do {
                for try await (folders, snippets) in observation.values(in: dbQueue) {
                    guard let self else { return }
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
        memoryObservationTask?.cancel()
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
            clearItem.setAccessibilityLabel(String(localized: "Clear all clipboard history"))
            menu.addItem(clearItem)
        }

        // Snippet section with header
        menu.addItem(NSMenuItem.separator())
        addSnippetMenuItems(to: menu)

        // Memory section (below snippets)
        menu.addItem(NSMenuItem.separator())
        addMemoryMenuItems(to: menu)

        // Bottom section: Edit Snippets, Preferences, Quit
        menu.addItem(NSMenuItem.separator())

        let editSnippetsItem = NSMenuItem(
            title: String(localized: "Edit Snippets\u{2026}"),
            action: #selector(editSnippetsClicked(_:)),
            keyEquivalent: "e"
        )
        editSnippetsItem.target = self
        editSnippetsItem.setAccessibilityLabel(String(localized: "Open snippet editor"))
        menu.addItem(editSnippetsItem)

        let prefsItem = NSMenuItem(
            title: String(localized: "Preferences\u{2026}"),
            action: #selector(preferencesClicked(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        prefsItem.setAccessibilityLabel(String(localized: "Open preferences"))
        menu.addItem(prefsItem)

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
            clearItem.setAccessibilityLabel(String(localized: "Clear all clipboard history"))
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
            keyEquivalent: "e"
        )
        editSnippetsItem.target = self
        menu.addItem(editSnippetsItem)
    }

    // MARK: - History Items

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

        // Inline items prefixed with letter keys for type-ahead
        let letterKeys = "abcdefghijklmnopqrstuvwxyz"
        for index in 0..<itemsInline {
            let prefix = index < letterKeys.count
                ? String(letterKeys[letterKeys.index(letterKeys.startIndex, offsetBy: index)])
                : ""
            let menuItem = buildMenuItem(for: displayItems[index], at: index, shortcutPrefix: prefix)
            menu.addItem(menuItem)

            // Option-alternate: show truncated title with 🧠 on the right
            let altItem = buildMemoryAlternateItem(for: displayItems[index], at: index, shortcutPrefix: prefix)
            menu.addItem(altItem)
        }

        // Remaining items in folders
        if itemsInline < displayItems.count {
            let remaining = Array(displayItems[itemsInline...])
            let chunks = remaining.chunked(into: folderSize)

            let submenuKeys = "1234567890abcdefghijklmnopqrstuvwxyz"

            for (chunkIndex, chunk) in chunks.enumerated() {
                let folderTitle = "\(chunkIndex + 1)"

                let folderItem = NSMenuItem(title: folderTitle, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: folderTitle)

                for (offset, item) in chunk.enumerated() {
                    let globalIndex = itemsInline + (chunkIndex * folderSize) + offset
                    let subPrefix = offset < submenuKeys.count
                        ? String(submenuKeys[submenuKeys.index(submenuKeys.startIndex, offsetBy: offset)])
                        : ""
                    let menuItem = buildMenuItem(for: item, at: globalIndex, shortcutPrefix: subPrefix)
                    submenu.addItem(menuItem)

                    // Option-alternate inside submenus
                    let altItem = buildMemoryAlternateItem(for: item, at: globalIndex, shortcutPrefix: subPrefix)
                    submenu.addItem(altItem)
                }

                folderItem.submenu = submenu
                menu.addItem(folderItem)
            }
        }
    }

    // MARK: - Snippet Items

    private func addSnippetMenuItems(to menu: NSMenu) {
        let rootSnippets = allSnippets.filter { $0.folderId == nil && $0.isEnabled }
        let enabledFolders = snippetFolders.filter(\.isEnabled)
        let hasAnySnippets = !rootSnippets.isEmpty || enabledFolders.contains { folder in
            allSnippets.contains { $0.folderId == folder.id && $0.isEnabled }
        }

        // "Snippets" section header
        let headerItem = NSMenuItem(title: String(localized: "Snippets"), action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let snippetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        headerItem.attributedTitle = NSAttributedString(string: String(localized: "Snippets"), attributes: snippetAttrs)
        menu.addItem(headerItem)

        guard hasAnySnippets else {
            let emptyItem = NSMenuItem(title: String(localized: "No Snippets"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        // Root-level snippets (no folder)
        for snippet in rootSnippets {
            let snippetItem = NSMenuItem(
                title: snippet.title,
                action: #selector(snippetClicked(_:)),
                keyEquivalent: ""
            )
            snippetItem.target = self
            snippetItem.representedObject = snippet.content
            menu.addItem(snippetItem)
        }

        // Folder submenus
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

    // MARK: - Memory Items

    private func addMemoryMenuItems(to menu: NSMenu) {
        // "Memory" section header
        let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let headerStr = NSMutableAttributedString()
        let brainAttachment = NSTextAttachment()
        let brainConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        if let brainImage = NSImage(systemSymbolName: "brain", accessibilityDescription: "Memory")?
            .withSymbolConfiguration(brainConfig) {
            brainImage.isTemplate = true
            brainAttachment.image = brainImage
        }
        headerStr.append(NSAttributedString(attachment: brainAttachment))
        headerStr.append(NSAttributedString(string: " Memory", attributes: attrs))
        headerItem.attributedTitle = headerStr
        menu.addItem(headerItem)

        guard !memoryItems.isEmpty else {
            let emptyItem = NSMenuItem(title: String(localized: "No memories yet"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        let maxMemorySize = Defaults[.maxMemorySize]
        let inlineCount = Defaults[.numberOfMemoryItemsInline]
        let folderSize = Defaults[.numberOfItemsPerMemoryFolder]

        let displayItems = Array(memoryItems.prefix(maxMemorySize))
        let itemsInline = inlineCount == 0 ? displayItems.count : min(inlineCount, displayItems.count)

        // Phase 1 — inline items labeled m1, m2, ...
        for index in 0..<itemsInline {
            let label = "m\(index + 1)"
            let menuItem = buildMemoryMenuItem(for: displayItems[index], label: label)
            menu.addItem(menuItem)

            let altItem = buildMemoryPromoteAlternate(for: displayItems[index], label: label)
            menu.addItem(altItem)
        }

        // Phase 2 — remaining items in folders
        if itemsInline < displayItems.count {
            let remaining = Array(displayItems[itemsInline...])
            let chunks = remaining.chunked(into: folderSize)

            for (chunkIndex, chunk) in chunks.enumerated() {
                let folderTitle = "m\(itemsInline + chunkIndex + 1)"
                let folderItem = NSMenuItem(title: folderTitle, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: folderTitle)

                for (offset, item) in chunk.enumerated() {
                    let subLabel = "\(offset + 1)"
                    let menuItem = buildMemoryMenuItem(for: item, label: subLabel)
                    submenu.addItem(menuItem)

                    let altItem = buildMemoryPromoteAlternate(for: item, label: subLabel)
                    submenu.addItem(altItem)
                }

                folderItem.submenu = submenu
                menu.addItem(folderItem)
            }
        }
    }

    private func buildMemoryMenuItem(for item: ClipItem, label: String) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let showTooltips = Defaults[.showTooltips]
        let tooltipMaxLen = Defaults[.tooltipMaxLength]

        let truncatedTitle = String(item.title.prefix(maxLen))
        let isMarkdown = MarkdownDetector.looksLikeMarkdown(item.stringValue ?? "")
        let mdPrefix = isMarkdown ? "MD " : ""
        let displayTitle = "\(label)  \(mdPrefix)\(truncatedTitle)"

        let menuItem = NSMenuItem(
            title: displayTitle,
            action: #selector(memoryItemClicked(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.representedObject = item.id

        if showTooltips, let str = item.stringValue {
            menuItem.toolTip = String(str.prefix(tooltipMaxLen))
        }

        return menuItem
    }

    private func buildMemoryPromoteAlternate(for item: ClipItem, label: String) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let shorterMax = max(20, maxLen - 6)
        let truncatedTitle = String(item.title.prefix(shorterMax))
        let displayTitle = "\(label)  \(truncatedTitle)"

        // SF Symbol arrow.right.doc.on.clipboard for "Move to Snippets"
        let titleStr = NSMutableAttributedString(string: "\(displayTitle)  ")
        let attachment = NSTextAttachment()
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let img = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: "Move to Snippets")?
            .withSymbolConfiguration(config) {
            img.isTemplate = true
            attachment.image = img
        }
        titleStr.append(NSAttributedString(attachment: attachment))

        let altItem = NSMenuItem(
            title: "",
            action: #selector(promoteMemoryClicked(_:)),
            keyEquivalent: ""
        )
        altItem.attributedTitle = titleStr
        altItem.keyEquivalentModifierMask = .option
        altItem.isAlternate = true
        altItem.target = self
        altItem.representedObject = item.id
        return altItem
    }

    // MARK: - Menu Item Builder

    private func buildMenuItem(for item: ClipItem, at index: Int, shortcutPrefix: String = "") -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let showImages = Defaults[.showImagesInMenu]
        let showTooltips = Defaults[.showTooltips]
        let tooltipMaxLen = Defaults[.tooltipMaxLength]

        // Truncate title to configured max length
        let truncatedTitle = String(item.title.prefix(maxLen))

        // Prefix with shortcut key for type-ahead navigation
        let displayTitle = shortcutPrefix.isEmpty
            ? truncatedTitle
            : "\(shortcutPrefix)  \(truncatedTitle)"

        let menuItem = NSMenuItem(
            title: displayTitle,
            action: #selector(historyItemClicked(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.tag = index

        // Show icon for image clips (blobs not loaded in lightweight queries)
        if showImages,
           item.primaryType == ClipContentType.tiff.rawValue
        {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: "Image")?
                .withSymbolConfiguration(config) {
                icon.isTemplate = true
                menuItem.image = icon
            }
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

        // Memory indicator (SF Symbol brain, monochrome)
        if item.isMemory {
            let brainAttachment = NSTextAttachment()
            let brainConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            if let brainImage = NSImage(systemSymbolName: "brain", accessibilityDescription: "Memory")?
                .withSymbolConfiguration(brainConfig) {
                brainImage.isTemplate = true
                brainAttachment.image = brainImage
            }
            let attributed = NSMutableAttributedString(attachment: brainAttachment)
            attributed.append(NSAttributedString(string: " " + menuItem.title))
            menuItem.attributedTitle = attributed
        }

        // Tooltip
        if showTooltips, let str = item.stringValue {
            menuItem.toolTip = String(str.prefix(tooltipMaxLen))
        }

        // Accessibility
        let typeLabel = item.primaryType
        let pinnedLabel = item.isPinned ? ", pinned" : ""
        let memoryLabel = item.isMemory ? ", memorized" : ""
        menuItem.setAccessibilityLabel("Clipboard item: \(item.title)\(pinnedLabel)\(memoryLabel), type: \(typeLabel)")

        return menuItem
    }

    /// Builds the Option-alternate menu item: shows a shorter clip title with a 🧠 on the right.
    private func buildMemoryAlternateItem(for item: ClipItem, at index: Int, shortcutPrefix: String) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        // Leave room for the brain suffix; show a good chunk of the original title
        let shorterMax = max(20, maxLen - 4)
        let truncatedTitle = String(item.title.prefix(shorterMax))
        let displayTitle = shortcutPrefix.isEmpty
            ? truncatedTitle
            : "\(shortcutPrefix)  \(truncatedTitle)"

        // Use an SF Symbol brain icon so it renders in monochrome menu style
        let titleStr = NSMutableAttributedString(string: "\(displayTitle)  ")
        let brainAttachment = NSTextAttachment()
        let brainConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let brainImage = NSImage(systemSymbolName: "brain", accessibilityDescription: "Save to Memory")?
            .withSymbolConfiguration(brainConfig) {
            brainImage.isTemplate = true
            brainAttachment.image = brainImage
        }
        titleStr.append(NSAttributedString(attachment: brainAttachment))

        let altItem = NSMenuItem(
            title: "",
            action: #selector(saveToMemoryClicked(_:)),
            keyEquivalent: ""
        )
        altItem.attributedTitle = titleStr
        altItem.keyEquivalentModifierMask = .option
        altItem.isAlternate = true
        altItem.target = self
        altItem.tag = index
        return altItem
    }

    // MARK: - Actions

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < historyItems.count else { return }
        pasteClipItem(historyItems[index])
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

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
    }

    @objc private func saveToMemoryClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < historyItems.count else { return }
        let item = historyItems[index]
        do {
            try databaseService.setMemory(clipId: item.id)
        } catch {
            Logger.database.error("Failed to save to memory: \(error.localizedDescription)")
        }
    }

    @objc private func editSnippetsClicked(_ sender: NSMenuItem) {
        snippetEditorWindow?.showWindow()
    }

    @objc private func preferencesClicked(_ sender: NSMenuItem) {
        preferencesWindow?.showWindow()
    }

    @objc private func clearAllClicked(_ sender: NSMenuItem) {
        do {
            try databaseService.deleteAll()
        } catch {
            Logger.database.error("Failed to clear history: \(error.localizedDescription)")
        }
    }

    @objc private func memoryItemClicked(_ sender: NSMenuItem) {
        guard let clipId = sender.representedObject as? String else { return }
        guard let item = memoryItems.first(where: { $0.id == clipId }) else { return }
        pasteClipItem(item)
    }

    @objc private func promoteMemoryClicked(_ sender: NSMenuItem) {
        guard let clipId = sender.representedObject as? String else { return }
        promoteMemoryToSnippet(clipId: clipId)
    }

    // MARK: - Memory Actions

    private func promoteMemoryToSnippet(clipId: String) {
        guard let item = memoryItems.first(where: { $0.id == clipId }) else { return }

        // Find or create the memory snippet folder
        let folderName = Defaults[.memorySnippetFolderName]
        let folder: SnippetFolder

        if let existing = snippetFolders.first(where: { $0.title == folderName }) {
            folder = existing
        } else {
            let nextIndex = (snippetFolders.last?.sortIndex ?? -1) + 1
            let newFolder = SnippetFolder(title: folderName, sortIndex: nextIndex)
            do {
                try databaseService.saveFolder(newFolder)
            } catch {
                Logger.database.error("Failed to create memory folder: \(error.localizedDescription)")
                return
            }
            folder = newFolder
        }

        let snippetCount = allSnippets.filter { $0.folderId == folder.id }.count
        do {
            try databaseService.promoteToSnippet(clipItem: item, folderId: folder.id, sortIndex: snippetCount)
        } catch {
            Logger.database.error("Failed to promote memory to snippet: \(error.localizedDescription)")
        }
    }

    // MARK: - Shared Paste Logic

    private func pasteClipItem(_ item: ClipItem) {
        // Fetch full item with blobs — observations only load lightweight columns
        let fullItem = (try? databaseService.fetchClipItem(id: item.id)) ?? item
        guard let changeCount = pasteService.writeToClipboard(fullItem) else { return }

        Task {
            await clipboardMonitor.updateLastSetChangeCount(changeCount)
        }

        // Reorder after paste: update the item's timestamp so it moves to top of history
        if Defaults[.reorderAfterPaste] {
            var updated = item
            updated.updatedAt = Date()
            try? databaseService.save(clip: updated)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
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
