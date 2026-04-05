import Foundation
import GRDB

struct Snippet: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: String
    var folderId: String?
    var title: String
    var content: String
    var sortIndex: Int
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(folderId: String? = nil, title: String = "Untitled Snippet", content: String = "", sortIndex: Int = 0) {
        self.id = UUID().uuidString
        self.folderId = folderId
        self.title = title
        self.content = content
        self.sortIndex = sortIndex
        self.isEnabled = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
