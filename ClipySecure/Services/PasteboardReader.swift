import AppKit
import Foundation

enum PasteboardReader: Sendable {
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @MainActor
    static func read(from pasteboard: NSPasteboard = .general) -> ClipContent? {
        guard let types = pasteboard.types else { return nil }

        if types.contains(concealedType) {
            return nil
        }

        let sourceAppId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        var detectedTypes: [ClipContentType] = []
        var stringValue: String?
        var rtfData: Data?
        var pdfData: Data?
        var imageData: Data?
        var filenames: [String]?
        var urls: [String]?

        // Read string
        if let str = pasteboard.string(forType: .string), !str.isEmpty {
            stringValue = str
            detectedTypes.append(.string)
        }

        // Read RTF
        if types.contains(.rtf), let data = pasteboard.data(forType: .rtf) {
            rtfData = data
            detectedTypes.append(.rtf)
            // Extract plain text from RTF if no string was found
            if stringValue == nil {
                let attrStr = NSAttributedString(rtf: data, documentAttributes: nil)
                stringValue = attrStr?.string
            }
        }

        // Read RTFD
        if types.contains(.rtfd), let data = pasteboard.data(forType: .rtfd) {
            if rtfData == nil {
                rtfData = data
            }
            if !detectedTypes.contains(.rtfd) {
                detectedTypes.append(.rtfd)
            }
        }

        // Read PDF
        if types.contains(.pdf), let data = pasteboard.data(forType: .pdf) {
            pdfData = data
            detectedTypes.append(.pdf)
        }

        // Read file URLs
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !fileURLs.isEmpty {
            filenames = fileURLs.map(\.path)
            detectedTypes.append(.filenames)
        }

        // Read URLs (non-file)
        if let urlStrings = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: false,
        ]) as? [URL] {
            let nonFileURLs = urlStrings.filter { !$0.isFileURL }
            if !nonFileURLs.isEmpty {
                urls = nonFileURLs.map(\.absoluteString)
                detectedTypes.append(.url)
            }
        }

        // Read image (TIFF/PNG)
        if types.contains(.tiff) || types.contains(.png) {
            let imgType: NSPasteboard.PasteboardType = types.contains(.png) ? .png : .tiff
            if let data = pasteboard.data(forType: imgType),
               let image = NSImage(data: data),
               let thumbnail = image.resizedToThumbnail()
            {
                imageData = thumbnail
                detectedTypes.append(.tiff)
            }
        }

        guard !detectedTypes.isEmpty else { return nil }

        // Determine primary type in priority order
        let primaryType: ClipContentType
        if filenames != nil {
            primaryType = .filenames
        } else if pdfData != nil {
            primaryType = .pdf
        } else if rtfData != nil && stringValue == nil {
            // Only RTF-primary if there's no string representation
            primaryType = .rtf
        } else if imageData != nil && stringValue == nil {
            primaryType = .tiff
        } else if urls != nil && stringValue == nil {
            primaryType = .url
        } else if stringValue != nil {
            primaryType = .string
        } else {
            primaryType = detectedTypes[0]
        }

        return ClipContent(
            primaryType: primaryType,
            stringValue: stringValue,
            rtfData: rtfData,
            pdfData: pdfData,
            imageData: imageData,
            filenames: filenames,
            urls: urls,
            sourceAppId: sourceAppId,
            types: detectedTypes
        )
    }
}
