import SwiftUI

struct SnippetEditorView: View {
    @Bindable var viewModel: SnippetEditorViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 500, minHeight: 350)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $viewModel.selectedSnippetId) {
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
        .toolbar {
            ToolbarItemGroup {
                Button(action: viewModel.addFolder) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                Button(action: viewModel.addSnippet) {
                    Label("Add Snippet", systemImage: "doc.badge.plus")
                }
                .disabled(viewModel.selectedFolderId == nil)
                Button(action: viewModel.deleteSelected) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedFolderId == nil && viewModel.selectedSnippetId == nil)
            }
        }
        .onChange(of: viewModel.selectedSnippetId) { _, newValue in
            if let snippetId = newValue,
               let snippet = viewModel.allSnippets.first(where: { $0.id == snippetId }),
               viewModel.selectedFolderId != snippet.folderId
            {
                viewModel.selectedFolderId = snippet.folderId
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
        } else {
            Text("Select a snippet to edit")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 8) {
            TextField("Snippet Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: title) { _, newValue in
                    onTitleChange(newValue)
                }

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .onChange(of: content) { _, newValue in
                    onContentChange(newValue)
                }
        }
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
