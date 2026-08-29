import SwiftUI

struct SnippetEditorView: View {
    @Bindable var viewModel: SnippetEditorViewModel

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
                Button(action: viewModel.deleteSelected) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedFolderId == nil && viewModel.selectedSnippetId == nil)
            }
        }
        .frame(minWidth: 600, minHeight: 450)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $viewModel.selectedSnippetId) {
            // Root-level snippets section
            Section("Snippets") {
                ForEach(viewModel.rootSnippets) { snippet in
                    Text(snippet.title)
                        .tag(snippet.id)
                }

                if viewModel.rootSnippets.isEmpty {
                    Text("No root snippets")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectRoot()
            }

            // Folder sections
            ForEach(viewModel.folders) { folder in
                DisclosureGroup {
                    ForEach(viewModel.snippets(inFolder: folder.id)) { snippet in
                        Text(snippet.title)
                            .tag(snippet.id)
                    }
                } label: {
                    Label(folder.title, systemImage: "folder")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectFolder(folder.id)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: viewModel.selectedSnippetId) { _, newValue in
            if let snippetId = newValue,
               let snippet = viewModel.allSnippets.first(where: { $0.id == snippetId })
            {
                if let folderId = snippet.folderId {
                    if viewModel.selectedFolderId != folderId {
                        viewModel.selectedFolderId = folderId
                    }
                    viewModel.isRootSelected = false
                } else {
                    viewModel.selectedFolderId = nil
                    viewModel.isRootSelected = true
                }
            }
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

    var body: some View {
        Form {
            Section("Folder") {
                TextField("Folder Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
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
        }
        .onChange(of: folder.id) { _, _ in
            title = folder.title
            isEnabled = folder.isEnabled
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
