import Foundation
import GRDB

struct SnippetFolder: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: String
    var title: String
    var sortIndex: Int
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(title: String = "Untitled Folder", sortIndex: Int = 0) {
        self.id = UUID().uuidString
        self.title = title
        self.sortIndex = sortIndex
        self.isEnabled = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
