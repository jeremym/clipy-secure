import SwiftUI

private enum SnippetContainer: Hashable {
    case root
    case folder(String)
}

struct SnippetEditorView: View {
    @Bindable var viewModel: SnippetEditorViewModel
    @State private var expandedFolderIds: Set<String> = []
    @State private var targetedContainer: SnippetContainer?
    @State private var targetedSnippetId: String?
    /// Set when the user asks to delete a folder that still holds snippets, so
    /// the cascade is confirmed rather than silent (review #13).
    @State private var folderPendingDelete: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: viewModel.addFolder) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                Button(action: viewModel.addSnippet) {
                    Label("Add Snippet", systemImage: "doc.badge.plus")
                }
                Button(action: attemptDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedFolderId == nil && viewModel.selectedSnippetId == nil)
            }
        }
        .confirmationDialog(
            "Delete this folder and its snippets?",
            isPresented: deleteConfirmationBinding,
            presenting: folderPendingDelete
        ) { folderId in
            Button("Delete Folder", role: .destructive) {
                viewModel.deleteFolder(folderId)
                folderPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                folderPendingDelete = nil
            }
        } message: { folderId in
            let count = viewModel.snippets(inFolder: folderId).count
            Text("\(count) snippet\(count == 1 ? "" : "s") in this folder will also be deleted. This can't be undone.")
        }
        .frame(minWidth: 600, minHeight: 450)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { folderPendingDelete != nil },
            set: { if !$0 { folderPendingDelete = nil } }
        )
    }

    /// Deletes the selection, but routes a folder that still has snippets through
    /// a confirmation first. Snippets and empty folders delete immediately.
    private func attemptDelete() {
        if let folderId = viewModel.selectedFolderId, viewModel.folderHasSnippets(folderId) {
            folderPendingDelete = folderId
        } else {
            viewModel.deleteSelected()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        // One enum-typed selection binding drives the whole list, so folder rows
        // and the root row take the AppKit selection highlight for free — no
        // onTapGesture shims, no desync between folder and snippet selection.
        List(selection: $viewModel.selection) {
            Section {
                // Explicit, selectable root row so the "no folder" destination is
                // discoverable instead of hidden behind the section header.
                Label("Top level (no folder)", systemImage: "tray")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(SnippetSidebarSelection.root)
                    .background(dropTargetBackground(for: .root))
                    .dropDestination(
                        for: String.self,
                        action: { items, _ in
                            moveDroppedSnippets(
                                items,
                                toFolder: nil,
                                atIndex: viewModel.rootSnippets.count
                            )
                        },
                        isTargeted: { isTargeted in
                            setDropTarget(.root, isTargeted: isTargeted)
                        }
                    )

                ForEach(viewModel.rootSnippets) { snippet in
                    snippetRow(snippet, inFolder: nil)
                }
            } header: {
                Text("Snippets")
            }

            // Folder sections
            ForEach(viewModel.folders) { folder in
                DisclosureGroup(isExpanded: expansionBinding(for: folder.id)) {
                    ForEach(viewModel.snippets(inFolder: folder.id)) { snippet in
                        snippetRow(snippet, inFolder: folder.id)
                    }
                } label: {
                    Label(folder.title, systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(SnippetSidebarSelection.folder(folder.id))
                        .background(dropTargetBackground(for: .folder(folder.id)))
                        .dropDestination(
                            for: String.self,
                            action: { items, _ in
                                moveDroppedSnippets(
                                    items,
                                    toFolder: folder.id,
                                    atIndex: viewModel.snippets(inFolder: folder.id).count
                                )
                            },
                            isTargeted: { isTargeted in
                                setDropTarget(.folder(folder.id), isTargeted: isTargeted)
                            }
                        )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
    }

    private func snippetRow(_ snippet: Snippet, inFolder folderId: String?) -> some View {
        Text(snippet.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(SnippetSidebarSelection.snippet(snippet.id))
            .draggable(snippet.id)
            .overlay(alignment: .top) {
                if targetedSnippetId == snippet.id {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
            .dropDestination(
                for: String.self,
                action: { items, _ in
                    let destinationSnippets = folderId.map(viewModel.snippets(inFolder:))
                        ?? viewModel.rootSnippets
                    guard let destinationIndex = destinationSnippets.firstIndex(where: {
                        $0.id == snippet.id
                    }) else {
                        return false
                    }
                    return moveDroppedSnippets(
                        items,
                        toFolder: folderId,
                        atIndex: destinationIndex
                    )
                },
                isTargeted: { isTargeted in
                    setDropTarget(snippetId: snippet.id, isTargeted: isTargeted)
                }
            )
    }

    private func expansionBinding(for folderId: String) -> Binding<Bool> {
        Binding(
            get: { expandedFolderIds.contains(folderId) },
            set: { isExpanded in
                if isExpanded {
                    expandedFolderIds.insert(folderId)
                } else {
                    expandedFolderIds.remove(folderId)
                }
            }
        )
    }

    private func moveDroppedSnippets(
        _ snippetIds: [String],
        toFolder folderId: String?,
        atIndex index: Int
    ) -> Bool {
        guard snippetIds.count == 1, let snippetId = snippetIds.first else { return false }
        let didMove = viewModel.moveSnippet(snippetId, toFolder: folderId, atIndex: index)
        guard didMove else { return false }

        if let folderId {
            expandedFolderIds.insert(folderId)
        }
        targetedContainer = nil
        targetedSnippetId = nil
        return true
    }

    private func setDropTarget(_ container: SnippetContainer, isTargeted: Bool) {
        if isTargeted {
            targetedContainer = container
        } else if targetedContainer == container {
            targetedContainer = nil
        }
    }

    private func setDropTarget(snippetId: String, isTargeted: Bool) {
        if isTargeted {
            targetedSnippetId = snippetId
        } else if targetedSnippetId == snippetId {
            targetedSnippetId = nil
        }
    }

    @ViewBuilder
    private func dropTargetBackground(for container: SnippetContainer) -> some View {
        if targetedContainer == container {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.18))
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let snippet = viewModel.selectedSnippet {
            SnippetDetailView(
                snippet: snippet,
                onTitleChange: { viewModel.updateSnippetTitle(snippet.id, title: $0) },
                onContentChange: { viewModel.updateSnippetContent(snippet.id, content: $0) }
            )
        } else if let folderId = viewModel.selectedFolderId,
                  let folder = viewModel.folders.first(where: { $0.id == folderId }) {
            FolderDetailView(
                folder: folder,
                snippetCount: viewModel.snippets(inFolder: folderId).count,
                onTitleChange: { viewModel.updateFolderTitle(folderId, title: $0) },
                onEnabledChange: { viewModel.updateFolderEnabled(folderId, isEnabled: $0) }
            )
        } else if viewModel.isRootSelected {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Root Snippets")
                    .font(.title3)
                Text("Snippets here appear directly in the menu, not inside a folder.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Click \"+\" to add a snippet.")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Select a snippet, folder, or create one to get started")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Folder Detail

private struct FolderDetailView: View {
    let folder: SnippetFolder
    let snippetCount: Int
    let onTitleChange: (String) -> Void
    let onEnabledChange: (Bool) -> Void

    @State private var title: String = ""
    @State private var isEnabled: Bool = true
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section("Folder") {
                TextField("Folder Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($nameFocused)
                    .onChange(of: title) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onTitleChange(trimmed)
                        }
                    }

                Toggle("Enabled", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        onEnabledChange(newValue)
                    }
            }

            Section("Info") {
                LabeledContent("Snippets", value: "\(snippetCount)")
                LabeledContent("Created", value: folder.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: folder.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            title = folder.title
            isEnabled = folder.isEnabled
            // Land the cursor in the name field so a freshly added folder can be
            // renamed by typing straight away.
            nameFocused = true
        }
        .onChange(of: folder.id) { _, _ in
            title = folder.title
            isEnabled = folder.isEnabled
            nameFocused = true
        }
    }
}

// MARK: - Snippet Detail

private struct SnippetDetailView: View {
    let snippet: Snippet
    let onTitleChange: (String) -> Void
    let onContentChange: (String) -> Void

    @State private var title: String = ""
    @State private var content: String = ""

    var body: some View {
        Form {
            Section("Snippet") {
                TextField("Snippet Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .onChange(of: title) { _, newValue in
                        onTitleChange(newValue)
                    }
            }

            Section("Content") {
                ZStack(alignment: .topLeading) {
                    if content.isEmpty {
                        Text("Enter snippet content\u{2026}")
                            .foregroundStyle(.tertiary)
                            .font(.system(.body, design: .monospaced))
                            .padding(.top, 8)
                            .padding(.leading, 9)
                    }

                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(3)
                }
                .frame(minHeight: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .onChange(of: content) { _, newValue in
                    onContentChange(newValue)
                }
            }

            Section("Info") {
                LabeledContent("Created", value: snippet.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: snippet.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            title = snippet.title
            content = snippet.content
        }
        .onChange(of: snippet.id) { _, _ in
            title = snippet.title
            content = snippet.content
        }
    }
}
