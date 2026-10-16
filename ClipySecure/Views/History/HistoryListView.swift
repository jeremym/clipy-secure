import GRDB
import OSLog
import SwiftUI

struct HistoryListView: View {
    let databaseService: DatabaseService
    let clipboardMonitor: ClipboardMonitor
    let pasteService: PasteService
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var items: [ClipItem] = []
    @State private var debounceTask: Task<Void, Never>?
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search history\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onChange(of: searchText) { _, newValue in
                    debounceSearch(query: newValue)
                }

            if items.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No History" : "No Results",
                    systemImage: searchText.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Copied items will appear here." : "No clips match your search.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(items) { item in
                    ClipItemRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            pasteItem(item)
                        }
                        .contextMenu {
                            Button("Paste") { pasteItem(item) }
                            if item.isMemory {
                                Button("Remove from Memory") { removeFromMemory(item) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { deleteClip(item) }
                        }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 300, minHeight: 300)
        .onAppear { startObservation() }
        .onDisappear { stopObservation() }
    }

    private func startObservation() {
        guard searchText.isEmpty else { return }
        let observation = ValueObservation.tracking { db in
            try ClipItem
                .order(Column("updatedAt").desc)
                .limit(100)
                .fetchAll(db)
        }

        observationTask = Task {
            do {
                for try await fetchedItems in observation.values(in: databaseService.dbQueue) {
                    if searchText.isEmpty {
                        items = databaseService.decrypt(fetchedItems)
                    }
                }
            } catch {
                // Observation ended
            }
        }
    }

    private func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func debounceSearch(query: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            if query.isEmpty {
                startObservation()
            } else {
                observationTask?.cancel()
                observationTask = nil
                do {
                    items = try databaseService.searchClips(query: query)
                } catch {
                    Logger.database.error("Search failed: \(error.localizedDescription)")
                    items = []
                }
            }
        }
    }

    /// The safe home (per plan §6) for per-clip removal — a floating,
    /// non-activating panel, so acting here never disturbs the target app's
    /// focus the way a custom clip-menu item would. Closes review #2's gap: a
    /// memorised secret can be forgotten or deleted outright.
    private func removeFromMemory(_ item: ClipItem) {
        do {
            try databaseService.removeFromMemory(clipId: item.id)
        } catch {
            Logger.database.error("Failed to remove from memory: \(error.localizedDescription)")
        }
        refreshAfterMutation()
    }

    private func deleteClip(_ item: ClipItem) {
        do {
            try databaseService.deleteClip(id: item.id)
        } catch {
            Logger.database.error("Failed to delete clip: \(error.localizedDescription)")
        }
        refreshAfterMutation()
    }

    /// The live observation refreshes the unfiltered list on its own; an active
    /// search holds a snapshot, so re-run it to reflect the change.
    private func refreshAfterMutation() {
        guard !searchText.isEmpty else { return }
        do {
            items = try databaseService.searchClips(query: searchText)
        } catch {
            Logger.database.error("Search refresh after mutation failed: \(error.localizedDescription)")
        }
    }

    private func pasteItem(_ item: ClipItem) {
        guard let changeCount = pasteService.writeToClipboard(item) else { return }
        // Record synchronously so a poll can't re-capture what we just wrote.
        clipboardMonitor.noteSetChangeCount(changeCount)

        onDismiss()

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
    }
}
