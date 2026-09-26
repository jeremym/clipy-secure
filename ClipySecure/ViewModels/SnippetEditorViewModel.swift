import Foundation
import GRDB
import Observation
import OSLog

@Observable
@MainActor
final class SnippetEditorViewModel {
    var folders: [SnippetFolder] = []
    var allSnippets: [Snippet] = []
    var selectedFolderId: String?
    var selectedSnippetId: String?
    /// When true, the "root" section is selected (no folder)
    var isRootSelected: Bool = false

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
        selectedFolderId = folder.id
        selectedSnippetId = nil
        isRootSelected = false
    }

    func deleteFolder(_ folderId: String) {
        do {
            try databaseService.deleteFolder(id: folderId)
        } catch {
            Logger.database.error("Failed to delete folder: \(error.localizedDescription)")
        }
        if selectedFolderId == folderId {
            selectedFolderId = nil
            selectedSnippetId = nil
        }
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
        let folderSnippets: [Snippet]

        if isRootSelected || selectedFolderId == nil {
            folderId = nil
            folderSnippets = rootSnippets
        } else {
            folderId = selectedFolderId
            folderSnippets = snippets(inFolder: selectedFolderId!)
        }

        let nextIndex = (folderSnippets.last?.sortIndex ?? -1) + 1
        let snippet = Snippet(folderId: folderId, sortIndex: nextIndex)
        do {
            try databaseService.saveSnippet(snippet)
        } catch {
            Logger.database.error("Failed to add snippet: \(error.localizedDescription)")
        }
        selectedSnippetId = snippet.id
    }

    func deleteSnippet(_ snippetId: String) {
        cancelPendingSaves(for: snippetId)
        do {
            try databaseService.deleteSnippet(id: snippetId)
        } catch {
            Logger.database.error("Failed to delete snippet: \(error.localizedDescription)")
        }
        if selectedSnippetId == snippetId {
            selectedSnippetId = nil
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

        selectedSnippetId = snippetId
        selectedFolderId = folderId
        isRootSelected = folderId == nil
        return true
    }

    func selectFolder(_ folderId: String?) {
        selectedFolderId = folderId
        selectedSnippetId = nil
        isRootSelected = false
    }

    func selectRoot() {
        selectedFolderId = nil
        selectedSnippetId = nil
        isRootSelected = true
    }
}
