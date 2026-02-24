import Foundation
import GRDB

final class DatabaseService: Sendable {
    let dbQueue: DatabaseQueue

    init() throws {
        let appSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.appSupportDirectoryName)

        try FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        let dbPath = appSupportURL.appendingPathComponent("clipy.db").path
        dbQueue = try DatabaseQueue(path: dbPath)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-createClipItems") { db in
            try db.create(table: "clipItem") { t in
                t.primaryKey("id", .text)
                t.column("contentHash", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("primaryType", .text).notNull()
                t.column("stringValue", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    func save(clip: ClipItem) throws {
        try dbQueue.write { db in
            if var existing = try ClipItem
                .filter(Column("contentHash") == clip.contentHash)
                .fetchOne(db)
            {
                existing.updatedAt = Date()
                try existing.update(db)
            } else {
                try clip.insert(db)
            }
        }
    }

    func fetchHistory(limit: Int = Constants.defaultHistoryLimit) throws -> [ClipItem] {
        try dbQueue.read { db in
            try ClipItem
                .order(Column("updatedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func deleteAll() throws {
        _ = try dbQueue.write { db in
            try ClipItem.deleteAll(db)
        }
    }

    func deleteOldest(keeping limit: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM clipItem WHERE id NOT IN (
                        SELECT id FROM clipItem ORDER BY updatedAt DESC LIMIT ?
                    )
                    """,
                arguments: [limit]
            )
        }
    }
}
