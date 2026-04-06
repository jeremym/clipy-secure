import Foundation
import GRDB
import Observation

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
    private var saveTask: Task<Void, Never>?

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
                .order(Column("sortIndex").asc)
                .fetchAll(db)
            let snippets = try Snippet
                .order(Column("sortIndex").asc)
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
        try? databaseService.saveFolder(folder)
        selectedFolderId = folder.id
        selectedSnippetId = nil
        isRootSelected = false
    }

    func deleteFolder(_ folderId: String) {
        try? databaseService.deleteFolder(id: folderId)
        if selectedFolderId == folderId {
            selectedFolderId = nil
            selectedSnippetId = nil
        }
    }

    func updateFolderTitle(_ folderId: String, title: String) {
        guard var folder = folders.first(where: { $0.id == folderId }) else { return }
        folder.title = title
        folder.updatedAt = Date()
        try? databaseService.saveFolder(folder)
    }

    func updateFolderEnabled(_ folderId: String, isEnabled: Bool) {
        guard var folder = folders.first(where: { $0.id == folderId }) else { return }
        folder.isEnabled = isEnabled
        folder.updatedAt = Date()
        try? databaseService.saveFolder(folder)
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
        try? databaseService.saveSnippet(snippet)
        selectedSnippetId = snippet.id
    }

    func deleteSnippet(_ snippetId: String) {
        try? databaseService.deleteSnippet(id: snippetId)
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
        debounceSave(snippetId: snippetId) { snippet in
            snippet.content = content
        }
    }

    func updateSnippetTitle(_ snippetId: String, title: String) {
        debounceSave(snippetId: snippetId) { snippet in
            snippet.title = title
        }
    }

    private func debounceSave(snippetId: String, apply: @escaping (inout Snippet) -> Void) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard var snippet = allSnippets.first(where: { $0.id == snippetId }) else { return }
            apply(&snippet)
            snippet.updatedAt = Date()
            try? databaseService.saveSnippet(snippet)
        }
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
