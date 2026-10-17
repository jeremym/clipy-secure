import AppKit
import Defaults
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
                                Button("Forget") { forget(item) }
                            } else {
                                Button("Save to Memory") { saveToMemory(item) }
                            }
                            Button("Send to Obsidian") { sendToObsidian(item) }
                            Divider()
                            Button("Delete", role: .destructive) { deleteItem(item) }
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

    // MARK: - Context-menu actions

    private func saveToMemory(_ item: ClipItem) {
        do {
            try databaseService.setMemory(clipId: item.id)
        } catch {
            Logger.database.error("Failed to save to memory: \(error.localizedDescription)")
        }
    }

    private func forget(_ item: ClipItem) {
        do {
            try databaseService.removeFromMemory(clipId: item.id)
        } catch {
            Logger.database.error("Failed to forget memory item: \(error.localizedDescription)")
        }
    }

    private func deleteItem(_ item: ClipItem) {
        do {
            try databaseService.delete(clipId: item.id)
        } catch {
            Logger.database.error("Failed to delete clip: \(error.localizedDescription)")
        }
    }

    private func sendToObsidian(_ item: ClipItem) {
        guard let options = ObsidianExportService.Options.current() else {
            presentObsidianAlert(
                title: String(localized: "No Obsidian vault configured"),
                message: String(localized: "Choose a vault in Preferences \u{25B8} Obsidian first.")
            )
            return
        }

        // Fetch the full, decrypted clip so blob-backed clips export correctly.
        let full: ClipItem
        do {
            full = try databaseService.fetchClipItem(id: item.id) ?? item
        } catch {
            Logger.database.error("Failed to fetch clip for Obsidian export: \(error.localizedDescription)")
            full = item
        }

        do {
            let url = try ObsidianExportService.export(full, options: options)
            if Defaults[.obsidianRemoveFromMemory], full.isMemory {
                do {
                    try databaseService.removeFromMemory(clipId: full.id)
                } catch {
                    Logger.database.error("Failed to remove from memory after Obsidian export: \(error.localizedDescription)")
                }
            }
            if Defaults[.obsidianOpenAfterSave],
               let encoded = url.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let obsidianURL = URL(string: "obsidian://open?path=\(encoded)") {
                NSWorkspace.shared.open(obsidianURL)
            }
        } catch {
            Logger.general.error("Obsidian export failed: \(error.localizedDescription)")
            presentObsidianAlert(
                title: String(localized: "Couldn't send to Obsidian"),
                message: String(localized: "Check the vault folder in Preferences \u{25B8} Obsidian.")
            )
        }
    }

    private func presentObsidianAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
