import Foundation
import GRDB

struct ExcludedApp: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: String
    var bundleId: String
    var appName: String
    var createdAt: Date

    init(bundleId: String, appName: String) {
        self.id = UUID().uuidString
        self.bundleId = bundleId
        self.appName = appName
        self.createdAt = Date()
    }
}
