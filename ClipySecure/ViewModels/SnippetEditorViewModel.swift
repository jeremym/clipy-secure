import Foundation
import GRDB
import Observation
import OSLog

/// One value drives the sidebar's `List(selection:)`. Giving folders and
/// snippets distinct cases (rather than a bare `String`) is what lets a folder
/// row take the selection highlight without being mistaken for a snippet id —
/// the root cause of the "click a folder, nothing highlights / Delete no-ops"
/// bug (review #12).
enum SnippetSidebarSelection: Hashable {
    case root
    case folder(String)
    case snippet(String)
}

@Observable
@MainActor
final class SnippetEditorViewModel {
    var folders: [SnippetFolder] = []
    var allSnippets: [Snippet] = []

    /// The single source of truth for what the sidebar has selected.
    var selection: SnippetSidebarSelection?

    // The rest of the app still reads these three; they are now derived from
    // `selection` instead of being independent stored state that could desync.
    var selectedSnippetId: String? {
        if case .snippet(let id) = selection { return id }
        return nil
    }

    var selectedFolderId: String? {
        if case .folder(let id) = selection { return id }
        return nil
    }

    var isRootSelected: Bool {
        selection == .root
    }

    private let databaseService: DatabaseService
    private var observationTask: Task<Void, Never>?
    private var saveTasks: [SnippetSaveKey: Task<Void, Never>] = [:]

    private enum SnippetEditField: Hashable {
        case title
        case content
    }

    private struct SnippetSaveKey: Hashable {
        let snippetId: String
        let field: SnippetEditField
    }

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
        startObservation()
    }

    // MARK: - Computed

    var rootSnippets: [Snippet] {
        allSnippets.filter { $0.folderId == nil }
    }

    func snippets(inFolder folderId: String) -> [Snippet] {
        allSnippets.filter { $0.folderId == folderId }
    }

    var selectedSnippet: Snippet? {
        guard let id = selectedSnippetId else { return nil }
        return allSnippets.first { $0.id == id }
    }

    // MARK: - Observation

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> ([SnippetFolder], [Snippet]) in
            let folders = try SnippetFolder
                .order(
                    Column("sortIndex").asc,
                    Column("createdAt").asc,
                    Column("id").asc
                )
                .fetchAll(db)
            let snippets = try Snippet
                .order(
                    Column("sortIndex").asc,
                    Column("createdAt").asc,
                    Column("id").asc
                )
                .fetchAll(db)
            return (folders, snippets)
        }

        let dbQueue = databaseService.dbQueue
        observationTask = Task { [weak self] in
            do {
                for try await (folders, snippets) in observation.values(in: dbQueue) {
                    guard let self else { return }
                    self.folders = folders
                    self.allSnippets = snippets
                }
            } catch {
                // Observation ended
            }
        }
    }

    // MARK: - Folder Actions

    func addFolder() {
        let nextIndex = (folders.last?.sortIndex ?? -1) + 1
        let folder = SnippetFolder(sortIndex: nextIndex)
        do {
            try databaseService.saveFolder(folder)
        } catch {
            Logger.database.error("Failed to add folder: \(error.localizedDescription)")
        }
        selection = .folder(folder.id)
    }

    func deleteFolder(_ folderId: String) {
        do {
            try databaseService.deleteFolder(id: folderId)
        } catch {
            Logger.database.error("Failed to delete folder: \(error.localizedDescription)")
        }
        if selectedFolderId == folderId {
            selection = nil
        }
    }

    /// Whether deleting `folderId` would cascade-delete snippets, so the UI can
    /// confirm first (review #13).
    func folderHasSnippets(_ folderId: String) -> Bool {
        allSnippets.contains { $0.folderId == folderId }
    }

    func updateFolderTitle(_ folderId: String, title: String) {
        guard var folder = folders.first(where: { $0.id == folderId }) else { return }
        folder.title = title
        folder.updatedAt = Date()
        do {
            try databaseService.saveFolder(folder)
        } catch {
            Logger.database.error("Failed to update folder title: \(error.localizedDescription)")
        }
    }

    func updateFolderEnabled(_ folderId: String, isEnabled: Bool) {
        guard var folder = folders.first(where: { $0.id == folderId }) else { return }
        folder.isEnabled = isEnabled
        folder.updatedAt = Date()
        do {
            try databaseService.saveFolder(folder)
        } catch {
            Logger.database.error("Failed to update folder enabled state: \(error.localizedDescription)")
        }
    }

    // MARK: - Snippet Actions

    func addSnippet() {
        let folderId: String?

        switch selection {
        case .folder(let id):
            folderId = id
        case .snippet(let id):
            // Add alongside the selected snippet, in whatever folder it lives in.
            folderId = allSnippets.first { $0.id == id }?.folderId
        case .root:
            folderId = nil
        case nil:
            // Nothing selected: nudge toward folders rather than silently adding
            // at the root. Target the first folder, creating "My Snippets" if
            // there are none yet.
            guard let targetFolder = folders.first ?? createDefaultFolder() else { return }
            folderId = targetFolder.id
        }

        let folderSnippets = folderId.map(snippets(inFolder:)) ?? rootSnippets
        let nextIndex = (folderSnippets.last?.sortIndex ?? -1) + 1
        let snippet = Snippet(folderId: folderId, sortIndex: nextIndex)
        do {
            try databaseService.saveSnippet(snippet)
        } catch {
            Logger.database.error("Failed to add snippet: \(error.localizedDescription)")
        }
        selection = .snippet(snippet.id)
    }

    /// Creates the "My Snippets" fallback folder when the user adds a snippet
    /// with nothing selected and no folders exist. Returns nil only if the write
    /// failed. The observation refreshes `folders` shortly after.
    private func createDefaultFolder() -> SnippetFolder? {
        let nextIndex = (folders.last?.sortIndex ?? -1) + 1
        let folder = SnippetFolder(title: String(localized: "My Snippets"), sortIndex: nextIndex)
        do {
            try databaseService.saveFolder(folder)
            return folder
        } catch {
            Logger.database.error("Failed to create default folder: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteSnippet(_ snippetId: String) {
        cancelPendingSaves(for: snippetId)
        do {
            try databaseService.deleteSnippet(id: snippetId)
        } catch {
            Logger.database.error("Failed to delete snippet: \(error.localizedDescription)")
        }
        if selectedSnippetId == snippetId {
            selection = nil
        }
    }

    func deleteSelected() {
        if let snippetId = selectedSnippetId {
            deleteSnippet(snippetId)
        } else if let folderId = selectedFolderId {
            deleteFolder(folderId)
        }
    }

    func updateSnippetContent(_ snippetId: String, content: String) {
        let key = SnippetSaveKey(snippetId: snippetId, field: .content)
        debounceSave(key: key) { [databaseService] in
            try databaseService.updateSnippetContent(id: snippetId, content: content)
        }
    }

    func updateSnippetTitle(_ snippetId: String, title: String) {
        let key = SnippetSaveKey(snippetId: snippetId, field: .title)
        debounceSave(key: key) { [databaseService] in
            try databaseService.updateSnippetTitle(id: snippetId, title: title)
        }
    }

    private func debounceSave(key: SnippetSaveKey, save: @escaping () throws -> Void) {
        saveTasks[key]?.cancel()
        saveTasks[key] = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch is CancellationError {
                return
            } catch {
                Logger.database.error("Failed while waiting to save snippet: \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled else { return }
            do {
                try save()
            } catch {
                Logger.database.error("Failed to save snippet: \(error.localizedDescription)")
            }
        }
    }

    private func cancelPendingSaves(for snippetId: String) {
        let keys = saveTasks.keys.filter { $0.snippetId == snippetId }
        for key in keys {
            saveTasks[key]?.cancel()
            saveTasks[key] = nil
        }
    }

    @discardableResult
    func moveSnippet(_ snippetId: String, toFolder folderId: String?, atIndex index: Int) -> Bool {
        guard allSnippets.contains(where: { $0.id == snippetId }) else { return false }
        if let folderId,
           !folders.contains(where: { $0.id == folderId }) {
            return false
        }

        do {
            try databaseService.moveSnippet(id: snippetId, toFolder: folderId, atIndex: index)
        } catch {
            Logger.database.error("Failed to move snippet: \(error.localizedDescription)")
            return false
        }

        selection = .snippet(snippetId)
        return true
    }

    func selectFolder(_ folderId: String) {
        selection = .folder(folderId)
    }

    func selectRoot() {
        selection = .root
    }
}
