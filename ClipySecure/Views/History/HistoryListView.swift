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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wroteContent = false

        if let rtfData = item.rtfData {
            pasteboard.setData(rtfData, forType: .rtf)
            wroteContent = true
        }
        if let pdfData = item.pdfData {
            pasteboard.setData(pdfData, forType: .pdf)
            wroteContent = true
        }
        if let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .png)
            wroteContent = true
        }
        if let filenamesStr = item.filenames,
           let data = filenamesStr.data(using: .utf8),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            let urls = paths.compactMap { URL(fileURLWithPath: $0) as NSURL }
            pasteboard.writeObjects(urls)
            wroteContent = true
        }
        if let stringValue = item.stringValue {
            pasteboard.setString(stringValue, forType: .string)
            wroteContent = true
        }

        guard wroteContent else { return }
        let changeCount = pasteboard.changeCount

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
