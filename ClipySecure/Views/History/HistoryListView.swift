import GRDB
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
                        items = fetchedItems
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
                let results = (try? databaseService.searchClips(query: query)) ?? []
                items = results
            }
        }
    }

    private func pasteItem(_ item: ClipItem) {
        guard let changeCount = pasteService.writeToClipboard(item) else { return }

        Task {
            await clipboardMonitor.updateLastSetChangeCount(changeCount)
        }

        onDismiss()

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            pasteService.paste()
        }
    }
}
