import AppKit
import Defaults

/// Builds NSMenu sections for history, snippets, and memory items.
/// Extracted from StatusBarController to keep menu construction logic separate
/// from observation, actions, and status bar lifecycle.
@MainActor
struct ClipMenuBuilder {

    // MARK: - History Section

    static func addHistoryItems(
        to menu: NSMenu,
        items historyItems: [ClipItem],
        target: AnyObject,
        pasteAction: Selector,
        memoryAction: Selector
    ) {
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
            let menuItem = buildHistoryItem(for: displayItems[index], shortcutPrefix: prefix, target: target, action: pasteAction)
            menu.addItem(menuItem)

            let altItem = buildMemoryAlternateItem(for: displayItems[index], shortcutPrefix: prefix, target: target, action: memoryAction)
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
                    let subPrefix = offset < submenuKeys.count
                        ? String(submenuKeys[submenuKeys.index(submenuKeys.startIndex, offsetBy: offset)])
                        : ""
                    let menuItem = buildHistoryItem(for: item, shortcutPrefix: subPrefix, target: target, action: pasteAction)
                    submenu.addItem(menuItem)

                    let altItem = buildMemoryAlternateItem(for: item, shortcutPrefix: subPrefix, target: target, action: memoryAction)
                    submenu.addItem(altItem)
                }

                folderItem.submenu = submenu
                menu.addItem(folderItem)
            }
        }
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
        pasteAction: Selector,
        promoteAction: Selector
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

        let displayItems = Array(memoryItems.prefix(maxMemorySize))
        let itemsInline = inlineCount == 0 ? displayItems.count : min(inlineCount, displayItems.count)

        // Phase 1 — inline items labeled m1, m2, ...
        for index in 0..<itemsInline {
            let label = "m\(index + 1)"
            let menuItem = buildMemoryItem(for: displayItems[index], label: label, target: target, action: pasteAction)
            menu.addItem(menuItem)

            let altItem = buildMemoryPromoteAlternate(for: displayItems[index], label: label, target: target, action: promoteAction)
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
                    let menuItem = buildMemoryItem(for: item, label: subLabel, target: target, action: pasteAction)
                    submenu.addItem(menuItem)

                    let altItem = buildMemoryPromoteAlternate(for: item, label: subLabel, target: target, action: promoteAction)
                    submenu.addItem(altItem)
                }

                folderItem.submenu = submenu
                menu.addItem(folderItem)
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
        label: String,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let showTooltips = Defaults[.showTooltips]
        let tooltipMaxLen = Defaults[.tooltipMaxLength]

        let truncatedTitle = String(item.title.prefix(maxLen))
        let isMarkdown = MarkdownDetector.looksLikeMarkdown(item.stringValue ?? "")
        let mdPrefix = isMarkdown ? "MD " : ""
        let displayTitle = "\(label)  \(mdPrefix)\(truncatedTitle)"

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

        return menuItem
    }

    private static func buildMemoryPromoteAlternate(
        for item: ClipItem,
        label: String,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let maxLen = Defaults[.menuItemTitleMaxLength]
        let shorterMax = max(20, maxLen - 6)
        let truncatedTitle = String(item.title.prefix(shorterMax))
        let displayTitle = "\(label)  \(truncatedTitle)"

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

// MARK: - Array chunking helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
