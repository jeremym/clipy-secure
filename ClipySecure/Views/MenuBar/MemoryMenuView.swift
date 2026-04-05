import SwiftUI

struct MemoryMenuView: View {
    let items: [MemoryDisplayItem]
    let onPaste: (String) -> Void
    let onPromoteToSnippet: (String) -> Void

    private let folderSize = 20

    var body: some View {
        if items.isEmpty {
            Text("No memories yet")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let chunks = items.chunked(into: folderSize)
                    ForEach(Array(chunks.enumerated()), id: \.offset) { chunkIndex, chunk in
                        DisclosureGroup("\(chunkIndex + 1)") {
                            ForEach(chunk) { item in
                                MemoryItemRow(item: item) {
                                    onPaste(item.clipId)
                                } onOptionClick: {
                                    onPromoteToSnippet(item.clipId)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(width: 280, height: min(CGFloat(items.chunked(into: folderSize).count) * 28, 120))
        }
    }
}

// MARK: - Display model (avoids passing ClipItem directly to SwiftUI)

struct MemoryDisplayItem: Identifiable {
    let id: String
    let clipId: String
    let title: String
    let isMarkdown: Bool
    let memorizedAt: Date?
}

// MARK: - Row view

private struct MemoryItemRow: View {
    let item: MemoryDisplayItem
    let onTap: () -> Void
    let onOptionClick: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            if item.isMarkdown {
                Text("MD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 13))

            Spacer()

            if isHovered {
                Button {
                    onOptionClick()
                } label: {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Move to Snippets")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Array chunking (matches StatusBarController helper)

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
