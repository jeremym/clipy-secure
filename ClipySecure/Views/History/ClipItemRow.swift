import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 8) {
            typeIcon
                .frame(width: 20)

            if let imageData = item.imageData,
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(item.title)
                        .lineLimit(1)
                }
                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.primaryType {
        case ClipContentType.rtf.rawValue, ClipContentType.rtfd.rawValue:
            Image(systemName: "doc.richtext")
                .foregroundStyle(.blue)
        case ClipContentType.pdf.rawValue:
            Image(systemName: "doc.fill")
                .foregroundStyle(.red)
        case ClipContentType.filenames.rawValue:
            Image(systemName: "folder")
                .foregroundStyle(.blue)
        case ClipContentType.url.rawValue:
            Image(systemName: "link")
                .foregroundStyle(.purple)
        case ClipContentType.tiff.rawValue:
            Image(systemName: "photo")
                .foregroundStyle(.green)
        default:
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
        }
    }
}
