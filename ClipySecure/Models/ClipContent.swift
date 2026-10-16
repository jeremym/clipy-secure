import AppKit
import Foundation

enum ClipContentType: String, Codable, Sendable {
    case string
    case rtf
    case rtfd
    case pdf
    case filenames
    case url
    case tiff
}

struct ClipContent: Sendable {
    let primaryType: ClipContentType
    let stringValue: String?
    let rtfData: Data?
    let pdfData: Data?
    /// Full-resolution image bytes (PNG), so pasting a stored image is faithful.
    let imageData: Data?
    /// A small thumbnail derived from the full image, for display without
    /// loading the original. nil for non-image clips.
    let thumbnailData: Data?
    let filenames: [String]?
    let urls: [String]?
    let sourceAppId: String?
    let types: [ClipContentType]

    var title: String {
        switch primaryType {
        case .string:
            return stringValue?
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespaces)
                .truncated() ?? ""
        case .rtf, .rtfd:
            if let str = stringValue {
                return str
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespaces)
                    .truncated() ?? "(Rich Text)"
            }
            return "(Rich Text)"
        case .pdf:
            return "(PDF)"
        case .filenames:
            if let files = filenames, let first = files.first {
                let name = (first as NSString).lastPathComponent
                let suffix = files.count > 1 ? " +\(files.count - 1) more" : ""
                return (name + suffix).truncated()
            }
            return "(Files)"
        case .url:
            if let urlList = urls, let first = urlList.first {
                return first.truncated()
            }
            return "(URL)"
        case .tiff:
            return "(Image)"
        }
    }
}
