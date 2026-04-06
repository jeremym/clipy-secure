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

    // MARK: - Menu Assembly

    private func buildFullMenu(_ menu: NSMenu) {
        ClipMenuBuilder.addHistoryItems(
            to: menu,
            items: historyItems,
            target: self,
            pasteAction: #selector(historyItemClicked(_:)),
            memoryAction: #selector(saveToMemoryClicked(_:))
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
            memoryAction: #selector(saveToMemoryClicked(_:))
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
