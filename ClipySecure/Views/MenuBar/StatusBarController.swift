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
                    self.historyItems = self.databaseService.decrypt(items)
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
                    self.memoryItems = self.databaseService.decrypt(items)
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
        popUp(mode: .full)
    }

    func popUpHistoryMenu() {
        popUp(mode: .historyOnly)
    }

    func popUpSnippetMenu() {
        popUp(mode: .snippetsOnly)
    }

    /// Presents the clip menu for `mode`, either under the mouse pointer or from
    /// the status bar icon.
    ///
    /// Clicking the status item is the only way to anchor a menu *to* it, so the
    /// cursor case builds a detached menu instead. It shares `self` as delegate,
    /// so `menuNeedsUpdate(_:)` populates it identically — `menuMode` is read
    /// there, which is why it must be set first.
    private func popUp(mode: MenuMode) {
        menuMode = mode

        guard Defaults[.showMenuAtMousePointer] else {
            statusItem?.button?.performClick(nil)
            return
        }

        let menu = NSMenu()
        menu.delegate = self

        // Populate up front so `menu.size` is known before positioning. popUp
        // will call this again via the delegate; menuNeedsUpdate starts with
        // removeAllItems(), so rebuilding is idempotent.
        menuNeedsUpdate(menu)

        // A nil view means `at` is in screen coordinates, which is what
        // NSEvent.mouseLocation already reports. AppKit clamps horizontally on
        // its own, but vertically it just makes the menu scroll — so lift it
        // explicitly instead.
        menu.popUp(positioning: nil, at: originClearOfCursor(for: menu), in: nil)
    }

    /// Top-left corner for `menu` that keeps it on screen and out from under the
    /// pointer.
    ///
    /// A menu grows down and to the right of the point it is given, so near an
    /// edge macOS shifts it back over the cursor — which lands the pointer on
    /// some arbitrary row, pre-highlighted. Placing the menu diagonally off the
    /// cursor and picking the first corner that fits entirely inside the visible
    /// frame keeps the pointer clear and stops AppKit from moving it at all.
    private func originClearOfCursor(for menu: NSMenu) -> NSPoint {
        let cursor = NSEvent.mouseLocation

        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return cursor }

        let size = menu.size
        let gap = Self.menuCursorGap

        let corners = [
            NSPoint(x: cursor.x + gap, y: cursor.y - gap),                              // below right
            NSPoint(x: cursor.x - gap - size.width, y: cursor.y - gap),                 // below left
            NSPoint(x: cursor.x + gap, y: cursor.y + gap + size.height),                // above right
            NSPoint(x: cursor.x - gap - size.width, y: cursor.y + gap + size.height),   // above left
        ]

        if let fitting = corners.first(where: { visibleFrame.contains(rect(topLeft: $0, size: size)) }) {
            return fitting
        }

        // Taller than the screen allows in any corner: pin it to the top and
        // take whichever side leaves the pointer beside the menu rather than on
        // it. If neither side has room, clamping wins over an unreachable menu.
        let top = min(visibleFrame.maxY, max(visibleFrame.minY + size.height, cursor.y))
        if cursor.x + gap + size.width <= visibleFrame.maxX {
            return NSPoint(x: cursor.x + gap, y: top)
        }
        if cursor.x - gap - size.width >= visibleFrame.minX {
            return NSPoint(x: cursor.x - gap - size.width, y: top)
        }
        return NSPoint(x: min(cursor.x, visibleFrame.maxX - size.width), y: top)
    }

    /// Rect a menu occupies when `popUp` is handed `topLeft`.
    private func rect(topLeft: NSPoint, size: NSSize) -> NSRect {
        NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    }

    /// Diagonal offset between the pointer and the menu's nearest corner.
    private static let menuCursorGap: CGFloat = 8

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

    func menuWillOpen(_ menu: NSMenu) {
        MenuKeyRouter.shared.noteOpened(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        MenuKeyRouter.shared.noteClosed(menu)
        menuMode = .full
    }


    // MARK: - Menu Assembly

    private func buildFullMenu(_ menu: NSMenu) {
        ClipMenuBuilder.addHistoryItems(
            to: menu,
            items: historyItems,
            target: self,
            pasteAction: #selector(historyItemClicked(_:)),
            memoryAction: #selector(saveToMemoryClicked(_:)),
            folderAction: #selector(historyFolderKeyPressed(_:))
        )

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
        ClipMenuBuilder.addSnippetItems(
            to: menu,
            folders: snippetFolders,
            snippets: allSnippets,
            target: self,
            action: #selector(snippetClicked(_:))
        )

        // Memory section (below snippets)
        menu.addItem(NSMenuItem.separator())
        ClipMenuBuilder.addMemoryItems(
            to: menu,
            items: memoryItems,
            target: self,
            pasteAction: #selector(memoryItemClicked(_:)),
            promoteAction: #selector(promoteMemoryClicked(_:))
        )

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
        ClipMenuBuilder.addHistoryItems(
            to: menu,
            items: historyItems,
            target: self,
            pasteAction: #selector(historyItemClicked(_:)),
            memoryAction: #selector(saveToMemoryClicked(_:)),
            folderAction: #selector(historyFolderKeyPressed(_:))
        )

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
        ClipMenuBuilder.addSnippetItems(
            to: menu,
            folders: snippetFolders,
            snippets: allSnippets,
            target: self,
            action: #selector(snippetClicked(_:))
        )

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

    // MARK: - Actions

    @objc private func historyItemClicked(_ sender: NSMenuItem) {
        guard let clipId = sender.representedObject as? String,
              let item = historyItems.first(where: { $0.id == clipId }) else { return }
        pasteClipItem(item)
    }

    /// Opens a history folder in response to its digit key.
    ///
    /// Firing a key equivalent dismisses the whole menu, so the folder is
    /// re-presented on its own — landing where the menu already was, since the
    /// pointer has not moved.
    @objc private func historyFolderKeyPressed(_ sender: NSMenuItem) {
        guard let folderItem = sender.representedObject as? NSMenuItem,
              let submenu = folderItem.submenu else { return }

        // A menu cannot be displayed while it is still attached elsewhere. The
        // root menu is rebuilt from scratch on every open, so detaching costs
        // nothing.
        folderItem.submenu = nil

        // Present after the dismissal completes — popping up inside a tracking
        // session that is tearing down leaves the new menu unresponsive.
        Task { @MainActor [weak self] in
            guard let self else { return }
            submenu.popUp(positioning: nil, at: self.originClearOfCursor(for: submenu), in: nil)
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

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
    }

    @objc private func saveToMemoryClicked(_ sender: NSMenuItem) {
        guard let clipId = sender.representedObject as? String,
              historyItems.contains(where: { $0.id == clipId }) else { return }
        do {
            try databaseService.setMemory(clipId: clipId)
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
        let fullItem: ClipItem
        do {
            fullItem = try databaseService.fetchClipItem(id: item.id) ?? item
        } catch {
            Logger.database.error("Failed to fetch clip item: \(error.localizedDescription)")
            fullItem = item
        }
        guard let changeCount = pasteService.writeToClipboard(fullItem) else { return }

        Task {
            await clipboardMonitor.updateLastSetChangeCount(changeCount)
        }

        // Reorder after paste: update the item's timestamp so it moves to top of history
        if Defaults[.reorderAfterPaste] {
            do {
                try databaseService.touch(clipId: item.id)
            } catch {
                Logger.database.error("Failed to reorder clip after paste: \(error.localizedDescription)")
            }
        }

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
    }
}
