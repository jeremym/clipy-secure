import CryptoKit
import Foundation
import GRDB

struct ClipItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: String
    var contentHash: String
    var primaryType: String
    var createdAt: Date
    var updatedAt: Date

    // Phase 2 columns
    var types: String?
    var sourceAppId: String?
    var isPinned: Bool
    var isMemory: Bool
    var memorizedAt: Date?

    // Encrypted content columns — the only content that reaches disk.
    var encTitle: Data?
    var encStringValue: Data?
    var encRtfData: Data?
    var encPdfData: Data?
    var encImageData: Data?
    var encFilenames: Data?
    var encUrls: Data?

    // Plaintext content — in-memory only. Excluded from CodingKeys so GRDB
    // can neither read nor write these as columns; DatabaseService populates
    // them by decrypting the enc* columns.
    var title: String = ""
    var stringValue: String? = nil
    var rtfData: Data? = nil
    var pdfData: Data? = nil
    var imageData: Data? = nil
    var filenames: String? = nil
    var urls: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, contentHash, primaryType, createdAt, updatedAt
        case types, sourceAppId, isPinned, isMemory, memorizedAt
        case encTitle, encStringValue, encRtfData, encPdfData, encImageData
        case encFilenames, encUrls
    }

    // MARK: - Text-only initializer (Phase 1 compat)

    init(stringValue: String) {
        self.id = UUID().uuidString
        self.stringValue = stringValue
        self.contentHash = Self.computeHash(for: stringValue)
        self.title = stringValue
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces)
            .truncated() ?? ""
        self.primaryType = "string"
        self.createdAt = Date()
        self.updatedAt = Date()
        self.types = Self.encodeTypes([.string])
        self.isPinned = false
        self.isMemory = false
    }

    // MARK: - Full content initializer (Phase 2)

    init(content: ClipContent) {
        self.id = UUID().uuidString
        self.primaryType = content.primaryType.rawValue
        self.title = content.title
        self.stringValue = content.stringValue
        self.rtfData = content.rtfData
        self.pdfData = content.pdfData
        self.imageData = content.imageData
        self.sourceAppId = content.sourceAppId
        self.isPinned = false
        self.isMemory = false
        self.createdAt = Date()
        self.updatedAt = Date()

        self.types = Self.encodeTypes(content.types)

        if let names = content.filenames {
            self.filenames = Self.encodeStringArray(names)
        }
        if let urlList = content.urls {
            self.urls = Self.encodeStringArray(urlList)
        }

        self.contentHash = Self.computeContentHash(content)
    }

    // MARK: - Hashing

    static func computeHash(for string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func computeContentHash(_ content: ClipContent) -> String {
        var hasher = SHA256()

        hasher.update(data: Data(content.primaryType.rawValue.utf8))

        if let str = content.stringValue {
            hasher.update(data: Data(str.utf8))
        }
        if let data = content.rtfData {
            hasher.update(data: data)
        }
        if let data = content.pdfData {
            hasher.update(data: data)
        }
        if let data = content.imageData {
            hasher.update(data: data)
        }
        if let names = content.filenames {
            hasher.update(data: Data(names.joined(separator: "\n").utf8))
        }
        if let urlList = content.urls {
            hasher.update(data: Data(urlList.joined(separator: "\n").utf8))
        }

        let hash = hasher.finalize()
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - JSON helpers for array columns

    static func encodeTypes(_ types: [ClipContentType]) -> String {
        let raw = types.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(raw),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    static func encodeStringArray(_ array: [String]) -> String {
        guard let data = try? JSONEncoder().encode(array),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    func decodedTypes() -> [ClipContentType] {
        guard let typesStr = types,
              let data = typesStr.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return raw.compactMap { ClipContentType(rawValue: $0) }
    }

    func decodedFilenames() -> [String] {
        guard let str = filenames,
              let data = str.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }

    func decodedURLs() -> [String] {
        guard let str = urls,
              let data = str.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }
}
