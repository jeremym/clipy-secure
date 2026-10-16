import AppKit
import Defaults

/// Builds NSMenu sections for history, snippets, and memory items.
/// Extracted from StatusBarController to keep menu construction logic separate
/// from observation, actions, and status bar lifecycle.
@MainActor
struct ClipMenuBuilder {

    // MARK: - History Section

    /// Builds the history section and returns the next free index into the shared
    /// shortcut-key sequence, so the memory section can continue keying rows where
    /// history left off instead of colliding with it.
    @discardableResult
    static func addHistoryItems(
        to menu: NSMenu,
        items historyItems: [ClipItem],
        target: AnyObject,
        pasteAction: Selector,
        memoryAction: Selector,
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
            let prefix = MenuShortcutKeys.key(at: index, in: shortcutKeys)
            let menuItem = buildHistoryItem(for: displayItems[index], shortcutPrefix: prefix, target: target, action: pasteAction)
            menu.addItem(menuItem)

            let altItem = buildMemoryAlternateItem(for: displayItems[index], shortcutPrefix: prefix, target: target, action: memoryAction)
            menu.addItem(altItem)
        }

        // Remaining items in folders
        guard itemsInline < displayItems.count else {
            // No overflow: the sequence is consumed only by the inline rows.
            return itemsInline
        }
        let remaining = Array(displayItems[itemsInline...])
        let chunks = remaining.chunked(into: folderSize)

        for (chunkIndex, chunk) in chunks.enumerated() {
            // Folder rows continue the same sequence the inline rows began,
            // so the first folder is keyed to whatever follows the last
            // inline item (e.g. inline 1–5 then folders 6, 7, …).
            let folderKey = MenuShortcutKeys.key(at: itemsInline + chunkIndex, in: shortcutKeys)
            let folderTitle = folderKey.isEmpty ? "\(chunkIndex + 1)" : folderKey

            let folderItem = NSMenuItem(title: folderTitle, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: folderTitle)

            for (offset, item) in chunk.enumerated() {
                // A submenu is its own key context — ancestors are suspended
                // while it is open — so its rows restart at the sequence head.
                let subPrefix = MenuShortcutKeys.key(at: offset, in: shortcutKeys)
                let menuItem = buildHistoryItem(for: item, shortcutPrefix: subPrefix, target: target, action: pasteAction)
                submenu.addItem(menuItem)

                let altItem = buildMemoryAlternateItem(for: item, shortcutPrefix: subPrefix, target: target, action: memoryAction)
                submenu.addItem(altItem)
            }

            MenuKeyRouter.attach(to: submenu)
            folderItem.submenu = submenu
            menu.addItem(folderItem)

            // AppKit never matches a key equivalent against an item that owns
            // a submenu, so the folder's key lives on a hidden sibling —
            // hidden items are still matched — whose action opens the folder.
            // With no key left in the sequence there is nothing to route, so
            // the opener is skipped (the folder still opens by click/arrow).
            if !folderKey.isEmpty {
                let opener = NSMenuItem(title: folderTitle, action: folderAction, keyEquivalent: "")
                opener.target = target
                opener.representedObject = folderItem
                opener.isHidden = true
                MenuKeyRouter.assign(key: folderKey, to: opener)
                menu.addItem(opener)
            }
        }

        // Inline rows plus one slot per folder — the first free index the memory
        // section continues from.
        return itemsInline + chunks.count
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

    /// Lays out the memory section. `startingKeyIndex` is where the shared
    /// shortcut sequence stands after the history section, so inline memory rows
    /// get real single-key shortcuts that continue past history instead of the
    /// old mouse-only `m1`/`m2` labels (review #6).
    static func addMemoryItems(
        to menu: NSMenu,
        items memoryItems: [ClipItem],
        startingKeyIndex: Int,
        target: AnyObject,
        pasteAction: Selector,
        promoteAction: Selector,
        folderAction: Selector
    ) {
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
        let shortcutKeys = MenuShortcutKeys.normalized(Defaults[.menuShortcutKeys])

        let displayItems = Array(memoryItems.prefix(maxMemorySize))

        // Unlike history, 0 here means "no inline rows — collapse the whole
        // section into one Memory ▸ submenu", not "show all inline" (review #6).
        let itemsInline = inlineCount == 0 ? 0 : min(inlineCount, displayItems.count)

        // Inline rows continue the shared sequence after the history section, so
        // they carry genuine single-key shortcuts (and the label shows the key).
        for index in 0..<itemsInline {
            let prefix = MenuShortcutKeys.key(at: startingKeyIndex + index, in: shortcutKeys)
            menu.addItem(buildMemoryItem(for: displayItems[index], shortcutPrefix: prefix, target: target, action: pasteAction))
            menu.addItem(buildMemoryPromoteAlternate(for: displayItems[index], shortcutPrefix: prefix, target: target, action: promoteAction))
        }

        // Everything past the inline rows lives in a single Memory ▸ submenu,
        // opened by the next key in the sequence via a hidden sibling (AppKit
        // won't match a key equivalent on a row that owns a submenu).
        guard itemsInline < displayItems.count else { return }
        let remaining = Array(displayItems[itemsInline...])

        let submenu = NSMenu(title: String(localized: "Memory"))
        fillMemorySubmenu(
            remaining,
            into: submenu,
            folderSize: folderSize,
            shortcutKeys: shortcutKeys,
            target: target,
            pasteAction: pasteAction,
            promoteAction: promoteAction,
            folderAction: folderAction
        )
        MenuKeyRouter.attach(to: submenu)

        let folderKey = MenuShortcutKeys.key(at: startingKeyIndex + itemsInline, in: shortcutKeys)
        let memoryLabel = String(localized: "Memory")
        let folderTitle = folderKey.isEmpty ? memoryLabel : "\(folderKey)  \(memoryLabel)"
        let folderItem = NSMenuItem(title: folderTitle, action: nil, keyEquivalent: "")
        folderItem.submenu = submenu
        menu.addItem(folderItem)

        if !folderKey.isEmpty {
            let opener = NSMenuItem(title: folderTitle, action: folderAction, keyEquivalent: "")
            opener.target = target
            opener.representedObject = folderItem
            opener.isHidden = true
            MenuKeyRouter.assign(key: folderKey, to: opener)
            menu.addItem(opener)
        }
    }

    /// Fills the Memory ▸ submenu. A submenu is its own key context — ancestors
    /// are suspended while it is open — so rows restart at the head of the
    /// sequence. Small lists go directly; larger lists chunk into sub-folders of
    /// `folderSize`, each keyed by the same hidden-opener trick.
    private static func fillMemorySubmenu(
        _ items: [ClipItem],
        into submenu: NSMenu,
        folderSize: Int,
        shortcutKeys: [Character],
        target: AnyObject,
        pasteAction: Selector,
        promoteAction: Selector,
        folderAction: Selector
    ) {
        if folderSize <= 0 || items.count <= folderSize {
            for (offset, item) in items.enumerated() {
                let prefix = MenuShortcutKeys.key(at: offset, in: shortcutKeys)
                submenu.addItem(buildMemoryItem(for: item, shortcutPrefix: prefix, target: target, action: pasteAction))
                submenu.addItem(buildMemoryPromoteAlternate(for: item, shortcutPrefix: prefix, target: target, action: promoteAction))
            }
            return
        }

        for (chunkIndex, chunk) in items.chunked(into: folderSize).enumerated() {
            let folderKey = MenuShortcutKeys.key(at: chunkIndex, in: shortcutKeys)
            let folderTitle = folderKey.isEmpty ? "\(chunkIndex + 1)" : folderKey
            let subfolderItem = NSMenuItem(title: folderTitle, action: nil, keyEquivalent: "")
            let subsubmenu = NSMenu(title: folderTitle)

            for (offset, item) in chunk.enumerated() {
                let prefix = MenuShortcutKeys.key(at: offset, in: shortcutKeys)
                subsubmenu.addItem(buildMemoryItem(for: item, shortcutPrefix: prefix, target: target, action: pasteAction))
                subsubmenu.addItem(buildMemoryPromoteAlternate(for: item, shortcutPrefix: prefix, target: target, action: promoteAction))
            }

            MenuKeyRouter.attach(to: subsubmenu)
            subfolderItem.submenu = subsubmenu
            submenu.addItem(subfolderItem)

            if !folderKey.isEmpty {
                let opener = NSMenuItem(title: folderTitle, action: folderAction, keyEquivalent: "")
                opener.target = target
                opener.representedObject = subfolderItem
                opener.isHidden = true
                MenuKeyRouter.assign(key: folderKey, to: opener)
                submenu.addItem(opener)
            }
        }
    }

    // MARK: - Individual Item Builders

    private static func buildHistoryItem(
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

        // The prefix is a shortcut, not decoration — typing it pastes at once.
        MenuKeyRouter.assign(key: shortcutPrefix, to: menuItem)

        return menuItem
    }

    private static func buildMemoryAlternateItem(
        for item: ClipItem,
        shortcutPrefix: String,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let shorterMax = max(20, maxLen - 4)
        let truncatedTitle = String(item.title.prefix(shorterMax))
        let displayTitle = shortcutPrefix.isEmpty
            ? truncatedTitle
            : "\(shortcutPrefix)  \(truncatedTitle)"

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
            action: action,
            keyEquivalent: ""
        )
        altItem.attributedTitle = titleStr
        altItem.keyEquivalentModifierMask = .option
        altItem.isAlternate = true
        altItem.target = target
        altItem.representedObject = item.id
        return altItem
    }

    private static func buildMemoryItem(
        for item: ClipItem,
        shortcutPrefix: String,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let showTooltips = Defaults[.showTooltips]
        let tooltipMaxLen = Defaults[.tooltipMaxLength]

        let truncatedTitle = String(item.title.prefix(maxLen))
        let isMarkdown = MarkdownDetector.looksLikeMarkdown(item.stringValue ?? "")
        let mdPrefix = isMarkdown ? "MD " : ""
        let displayTitle = shortcutPrefix.isEmpty
            ? "\(mdPrefix)\(truncatedTitle)"
            : "\(shortcutPrefix)  \(mdPrefix)\(truncatedTitle)"

        let menuItem = NSMenuItem(
            title: displayTitle,
            action: action,
            keyEquivalent: ""
        )
        menuItem.target = target
        menuItem.representedObject = item.id

        if showTooltips, let str = item.stringValue {
            menuItem.toolTip = String(str.prefix(tooltipMaxLen))
        }

        // The prefix is a real single-key shortcut (continuing the top-level
        // sequence, or restarting at the head inside a submenu) — typing it
        // pastes the memory at once, just like a history row.
        MenuKeyRouter.assign(key: shortcutPrefix, to: menuItem)

        return menuItem
    }

    private static func buildMemoryPromoteAlternate(
        for item: ClipItem,
        shortcutPrefix: String,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let shorterMax = max(20, maxLen - 6)
        let truncatedTitle = String(item.title.prefix(shorterMax))
        let displayTitle = shortcutPrefix.isEmpty
            ? truncatedTitle
            : "\(shortcutPrefix)  \(truncatedTitle)"

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
            action: action,
            keyEquivalent: ""
        )
        altItem.attributedTitle = titleStr
        altItem.keyEquivalentModifierMask = .option
        altItem.isAlternate = true
        altItem.target = target
        altItem.representedObject = item.id
        return altItem
    }
}

// MARK: - Menu shortcut key sequence

/// Resolves the single-key shortcuts shown beside clip-menu rows from the
/// user-configurable `menuShortcutKeys` string.
///
/// One ordered list drives the whole top level of the ⌘⇧V menu: the inline
/// history rows take the first characters, and the folder rows continue past
/// them — so a keystroke is never bound to two visible rows at once. Removing a
/// character from the sequence (a digit, say) frees that keystroke, which lets
/// AppKit type-selection jump to a snippet folder whose name starts with it
/// instead of the row previously claiming the key.
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

    /// How many slots of the shared sequence a top-level section of `itemCount`
    /// items consumes: one per inline row plus one per overflow folder. The
    /// memory section starts keying its rows from the history section's count, so
    /// a keystroke is never claimed by both. `inlineCount == 0` means all items
    /// are inline (history's convention); callers that collapse to a submenu at 0
    /// (memory) pass their own resolved inline count.
    static func topLevelSlots(itemCount: Int, inlineCount: Int, folderSize: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let inline = inlineCount == 0 ? itemCount : min(inlineCount, itemCount)
        let remaining = itemCount - inline
        let folders = (remaining > 0 && folderSize > 0)
            ? Int((Double(remaining) / Double(folderSize)).rounded(.up))
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
