import CryptoKit
import Foundation
import GRDB

struct ClipItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: String
    var contentHash: String
    var title: String
    var primaryType: String
    var stringValue: String?
    var createdAt: Date
    var updatedAt: Date

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
    }

    static func computeHash(for string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
