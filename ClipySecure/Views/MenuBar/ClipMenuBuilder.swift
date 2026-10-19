import AppKit
import Defaults

/// Builds NSMenu sections for history, snippets, and memory items.
/// Extracted from StatusBarController to keep menu construction logic separate
/// from observation, actions, and status bar lifecycle.
@MainActor
struct ClipMenuBuilder {

    /// The selectors a clip row wires up. Holding ⌥ on a row reveals a three-item
    /// submenu (m / o / d); the exact actions differ between history and memory
    /// rows, so the caller supplies the right selectors for each section.
    struct RowActions {
        let paste: Selector        // plain click / plain key
        let primary: Selector      // ⌥ m — Save to Memory (history) / Promote to Snippet (memory)
        let obsidian: Selector     // ⌥ o — Send to Obsidian
        let destructive: Selector  // ⌥ d — Delete (history) / Forget (memory)
        let openSubmenu: Selector  // ⌥ + row key — pop the row's action submenu detached
    }

    // MARK: - History Section

    /// Returns the next free shortcut-key index, so the memory section can
    /// continue the same sequence rather than clash with the history keys.
    @discardableResult
    static func addHistoryItems(
        to menu: NSMenu,
        items historyItems: [ClipItem],
        target: AnyObject,
        actions: RowActions,
        folderAction: Selector
    ) -> Int {
        let maxHistorySize = Defaults[.maxHistorySize]
        let displayItems = Array(historyItems.prefix(maxHistorySize))

        if displayItems.isEmpty {
            let emptyItem = NSMenuItem(title: String(localized: "No History"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return 0
        }

        let inlineCount = Defaults[.numberOfItemsInline]
        let folderSize = Defaults[.numberOfItemsInFolder]

        // If inlineCount is 0, show all items inline
        let itemsInline = inlineCount == 0 ? displayItems.count : min(inlineCount, displayItems.count)

        // One shared, user-configurable key sequence spans the whole top level:
        // inline rows take the first slots and folder rows continue after them,
        // so a keystroke is never claimed by two visible rows at once.
        let shortcutKeys = MenuShortcutKeys.normalized(Defaults[.menuShortcutKeys])

        for index in 0..<itemsInline {
            let key = MenuShortcutKeys.key(at: index, in: shortcutKeys)
            appendClipRow(displayItems[index], key: key, to: menu, target: target, actions: actions, memoryContext: false)
        }

        var nextKeyIndex = itemsInline

        // Remaining items in folders
        if itemsInline < displayItems.count {
            let remaining = Array(displayItems[itemsInline...])
            let chunks = remaining.chunked(into: folderSize)

            for (chunkIndex, chunk) in chunks.enumerated() {
                // Folder rows continue the same sequence the inline rows began,
                // so the first folder is keyed to whatever follows the last
                // inline item (e.g. inline 1–5 then folders 6, 7, …).
                let folderKey = MenuShortcutKeys.key(at: itemsInline + chunkIndex, in: shortcutKeys)
                let folderTitle = folderKey.isEmpty ? "\(chunkIndex + 1)" : folderKey
                addFolder(
                    titled: folderTitle, key: folderKey, items: chunk, to: menu,
                    target: target, actions: actions, folderAction: folderAction, memoryContext: false
                )
            }
            nextKeyIndex += chunks.count
        }

        return nextKeyIndex
    }

    // MARK: - Snippet Section

    static func addSnippetItems(
        to menu: NSMenu,
        folders: [SnippetFolder],
        snippets: [Snippet],
        target: AnyObject,
        action: Selector
    ) {
        let rootSnippets = snippets.filter { $0.folderId == nil && $0.isEnabled }
        let enabledFolders = folders.filter(\.isEnabled)
        let hasAnySnippets = !rootSnippets.isEmpty || enabledFolders.contains { folder in
            snippets.contains { $0.folderId == folder.id && $0.isEnabled }
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
                action: action,
                keyEquivalent: ""
            )
            snippetItem.target = target
            snippetItem.representedObject = snippet.content
            menu.addItem(snippetItem)
        }

        // Folder submenus
        for folder in enabledFolders {
            let folderSnippets = snippets.filter { $0.folderId == folder.id && $0.isEnabled }
            guard !folderSnippets.isEmpty else { continue }

            let folderItem = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: folder.title)

            for snippet in folderSnippets {
                let snippetItem = NSMenuItem(
                    title: snippet.title,
                    action: action,
                    keyEquivalent: ""
                )
                snippetItem.target = target
                snippetItem.representedObject = snippet.content
                submenu.addItem(snippetItem)
            }

            folderItem.submenu = submenu
            menu.addItem(folderItem)
        }
    }

    // MARK: - Memory Section

    static func addMemoryItems(
        to menu: NSMenu,
        items memoryItems: [ClipItem],
        target: AnyObject,
        actions: RowActions,
        folderAction: Selector,
        keyOffset: Int
    ) {
        menu.addItem(memoryHeaderItem())

        guard !memoryItems.isEmpty else {
            let emptyItem = NSMenuItem(title: String(localized: "No memories yet"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        let maxMemorySize = Defaults[.maxMemorySize]
        let inlineCount = Defaults[.numberOfMemoryItemsInline]
        let folderSize = Defaults[.numberOfItemsPerMemoryFolder]
        let shortcutKeys = MenuShortcutKeys.normalized(Defaults[.menuShortcutKeys])

        let displayItems = Array(memoryItems.prefix(maxMemorySize))

        // 0 means "collapse the whole section into one Memory ▸ submenu" — the
        // opposite of the history section's "0 = all inline", chosen so a user
        // who never uses Memory can tuck it out of the way with one setting.
        if inlineCount == 0 {
            let folderKey = MenuShortcutKeys.key(at: keyOffset, in: shortcutKeys)
            addFolder(
                titled: String(localized: "Memory"), key: folderKey, items: displayItems, to: menu,
                target: target, actions: actions, folderAction: folderAction, memoryContext: true
            )
            return
        }

        let itemsInline = min(inlineCount, displayItems.count)
        for index in 0..<itemsInline {
            // Inline memory rows continue the shared sequence after history, so
            // their single-key paste never collides with a history row's key.
            let key = MenuShortcutKeys.key(at: keyOffset + index, in: shortcutKeys)
            appendClipRow(displayItems[index], key: key, to: menu, target: target, actions: actions, memoryContext: true)
        }

        if itemsInline < displayItems.count {
            let remaining = Array(displayItems[itemsInline...])
            let chunks = remaining.chunked(into: folderSize)
            for (chunkIndex, chunk) in chunks.enumerated() {
                let folderKey = MenuShortcutKeys.key(at: keyOffset + itemsInline + chunkIndex, in: shortcutKeys)
                let folderTitle = folderKey.isEmpty ? "m\(chunkIndex + 1)" : folderKey
                addFolder(
                    titled: folderTitle, key: folderKey, items: chunk, to: menu,
                    target: target, actions: actions, folderAction: folderAction, memoryContext: true
                )
            }
        }
    }

    private static func memoryHeaderItem() -> NSMenuItem {
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
        return headerItem
    }

    // MARK: - Row + folder assembly

    /// Appends the four items that make up one clip row:
    ///   1. the visible base row (click / plain key → paste),
    ///   2. a keyless `isAlternate` row that owns the ⌥ action submenu,
    ///   3. a hidden plain-key opener (the base row is keyless so the key lives
    ///      here) and
    ///   4. a hidden ⌥+key opener that pops the action submenu detached.
    private static func appendClipRow(
        _ item: ClipItem,
        key: String,
        to menu: NSMenu,
        target: AnyObject,
        actions: RowActions,
        memoryContext: Bool
    ) {
        let base = buildBaseRow(for: item, shortcutPrefix: key, target: target, action: actions.paste)
        menu.addItem(base)

        let alt = buildActionAlternate(for: item, shortcutPrefix: key, target: target, actions: actions, memoryContext: memoryContext)
        menu.addItem(alt)

        guard !key.isEmpty else { return }

        let pasteOpener = NSMenuItem(title: "", action: actions.paste, keyEquivalent: "")
        pasteOpener.target = target
        pasteOpener.representedObject = item.id
        pasteOpener.isHidden = true
        MenuKeyRouter.assign(key: key, to: pasteOpener)
        menu.addItem(pasteOpener)

        let submenuOpener = NSMenuItem(title: "", action: actions.openSubmenu, keyEquivalent: "")
        submenuOpener.target = target
        // The handler detaches and re-pops this alternate's submenu.
        submenuOpener.representedObject = alt
        submenuOpener.isHidden = true
        MenuKeyRouter.assignOption(key: key, to: submenuOpener)
        menu.addItem(submenuOpener)
    }

    /// Builds a folder row whose submenu holds `items` (each a full clip row),
    /// keyed from the head of the sequence, plus the hidden opener that makes the
    /// folder's own key pop it open.
    private static func addFolder(
        titled folderTitle: String,
        key folderKey: String,
        items: [ClipItem],
        to menu: NSMenu,
        target: AnyObject,
        actions: RowActions,
        folderAction: Selector,
        memoryContext: Bool
    ) {
        let shortcutKeys = MenuShortcutKeys.normalized(Defaults[.menuShortcutKeys])
        let folderItem = NSMenuItem(title: folderTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: folderTitle)

        for (offset, item) in items.enumerated() {
            // A submenu is its own key context — ancestors are suspended while it
            // is open — so its rows restart at the sequence head.
            let subKey = MenuShortcutKeys.key(at: offset, in: shortcutKeys)
            appendClipRow(item, key: subKey, to: submenu, target: target, actions: actions, memoryContext: memoryContext)
        }

        MenuKeyRouter.attach(to: submenu)
        folderItem.submenu = submenu
        menu.addItem(folderItem)

        // AppKit never matches a key equivalent against an item that owns a
        // submenu, so the folder's key lives on a hidden sibling whose action
        // opens the folder. With no key left in the sequence the opener is
        // skipped (the folder still opens by click/arrow).
        if !folderKey.isEmpty {
            let opener = NSMenuItem(title: folderTitle, action: folderAction, keyEquivalent: "")
            opener.target = target
            opener.representedObject = folderItem
            opener.isHidden = true
            MenuKeyRouter.assign(key: folderKey, to: opener)
            menu.addItem(opener)
        }
    }

    // MARK: - Individual Item Builders

    private static func buildBaseRow(
        for item: ClipItem,
        shortcutPrefix: String,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let showImages = Defaults[.showImagesInMenu]
        let showTooltips = Defaults[.showTooltips]
        let tooltipMaxLen = Defaults[.tooltipMaxLength]

        let truncatedTitle = String(item.title.prefix(maxLen))
        let displayTitle = shortcutPrefix.isEmpty
            ? truncatedTitle
            : "\(shortcutPrefix)  \(truncatedTitle)"

        let menuItem = NSMenuItem(
            title: displayTitle,
            action: action,
            keyEquivalent: ""
        )
        menuItem.target = target
        // Address items by id, not index — the backing array is live-updated
        // by the observation and can shift while the menu is open.
        menuItem.representedObject = item.id

        // Show icon for image clips
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

        // Type indicator for non-text clips
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

        // Memory indicator (SF Symbol brain)
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

        // The base row is keyless: single-key paste rides on a hidden opener so
        // its keyless twin (the ⌥ alternate, which owns a submenu and therefore
        // can't hold a key equivalent) still pairs with it for the ⌥ swap.
        return menuItem
    }

    private static func buildActionAlternate(
        for item: ClipItem,
        shortcutPrefix: String,
        target: AnyObject,
        actions: RowActions,
        memoryContext: Bool
    ) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let shorterMax = max(20, maxLen - 4)
        let truncatedTitle = String(item.title.prefix(shorterMax))
        let displayTitle = shortcutPrefix.isEmpty
            ? truncatedTitle
            : "\(shortcutPrefix)  \(truncatedTitle)"

        let altItem = NSMenuItem(title: displayTitle, action: nil, keyEquivalent: "")
        altItem.keyEquivalentModifierMask = .option
        altItem.isAlternate = true
        altItem.target = target
        altItem.representedObject = item.id
        altItem.submenu = buildActionSubmenu(for: item, target: target, actions: actions, memoryContext: memoryContext)
        return altItem
    }

    /// The three-item ⌥ submenu: m / o / d. The labels differ between history
    /// and memory rows; the selectors are supplied by the caller via `actions`.
    private static func buildActionSubmenu(
        for item: ClipItem,
        target: AnyObject,
        actions: RowActions,
        memoryContext: Bool
    ) -> NSMenu {
        let submenu = NSMenu(title: String(localized: "Actions"))

        submenu.addItem(actionItem(
            title: memoryContext ? String(localized: "Promote to Snippet") : String(localized: "Save to Memory"),
            glyph: memoryContext ? "arrow.right.doc.on.clipboard" : "brain",
            key: "m", action: actions.primary, item: item, target: target
        ))
        submenu.addItem(actionItem(
            title: String(localized: "Send to Obsidian"),
            glyph: "book.closed",
            key: "o", action: actions.obsidian, item: item, target: target
        ))
        submenu.addItem(actionItem(
            title: memoryContext ? String(localized: "Forget") : String(localized: "Delete"),
            glyph: memoryContext ? "minus.circle" : "trash",
            key: "d", action: actions.destructive, item: item, target: target
        ))

        MenuKeyRouter.attach(to: submenu)
        return submenu
    }

    private static func actionItem(
        title: String,
        glyph: String,
        key: String,
        action: Selector,
        item: ClipItem,
        target: AnyObject
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = target
        menuItem.representedObject = item.id
        if let img = NSImage(systemSymbolName: glyph, accessibilityDescription: title) {
            img.isTemplate = true
            menuItem.image = img
        }
        MenuKeyRouter.assign(key: key, to: menuItem)
        return menuItem
    }
}

// MARK: - Menu shortcut key sequence

/// Resolves the single-key shortcuts shown beside clip-menu rows from the
/// user-configurable `menuShortcutKeys` string.
///
/// One ordered list drives the whole top level of the ⌘⇧V menu: the inline
/// history rows take the first characters, the history folder rows continue
/// past them, and the memory rows continue past those — so a keystroke is never
/// bound to two visible rows at once. Removing a character from the sequence (a
/// digit, say) frees that keystroke, which lets AppKit type-selection jump to a
/// snippet folder whose name starts with it instead of the row previously
/// claiming the key.
enum MenuShortcutKeys {
    /// Digits first, then letters — matches AppKit's single-character key
    /// equivalents, so 10 distinct keys (1–9, 0) are usable before letters.
    static let `default` = "1234567890abcdefghijklmnopqrstuvwxyz"

    /// The sequence with whitespace removed, lowercased, and de-duplicated
    /// (first occurrence wins). Lowercasing matches `MenuKeyRouter`, which keys
    /// case-insensitively, so "a" and "A" can't both resolve to the same key.
    static func normalized(_ raw: String) -> [Character] {
        var seen = Set<Character>()
        var result: [Character] = []
        for character in raw.lowercased() where !character.isWhitespace {
            if seen.insert(character).inserted {
                result.append(character)
            }
        }
        return result
    }

    /// The shortcut character at `index`, or "" when the sequence is shorter
    /// than the menu is long — extra rows simply carry no single-key shortcut.
    static func key(at index: Int, in keys: [Character]) -> String {
        guard index >= 0, index < keys.count else { return "" }
        return String(keys[index])
    }

    /// How many top-level key slots a section of `itemCount` items consumes:
    /// its inline rows plus one per folder. The memory section starts keying at
    /// the history section's slot count, so no key is claimed by two rows.
    /// `inlineCount == 0` means every row is inline (history's convention).
    static func topLevelSlots(itemCount: Int, inlineCount: Int, folderSize: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let inline = inlineCount == 0 ? itemCount : min(inlineCount, itemCount)
        let remaining = itemCount - inline
        let folders = (folderSize > 0 && remaining > 0)
            ? Int(ceil(Double(remaining) / Double(folderSize)))
            : 0
        return inline + folders
    }
}

// MARK: - Array chunking helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
