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

        // SQLCipher encryption key infrastructure is ready (EncryptionKeyManager).
        // Actual SQLCipher activation deferred — the standard GRDB SPM product does
        // not bundle SQLCipher; integrating it requires swapping to GRDBCipher or a
        // custom SQLite build. The key manager is wired so encryption can be enabled
        // in a follow-up with minimal changes:
        //
        //   let keyManager = EncryptionKeyManager()
        //   let key = try keyManager.getOrCreateDatabaseKey()
        //   var config = Configuration()
        //   config.prepareDatabase { db in
        //       try db.usePassphrase(key)
        //   }
        //   dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

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

        migrator.registerMigration("v2-addMultiTypeColumns") { db in
            try db.alter(table: "clipItem") { t in
                t.add(column: "types", .text).defaults(to: "[]")
                t.add(column: "rtfData", .blob)
                t.add(column: "pdfData", .blob)
                t.add(column: "imageData", .blob)
                t.add(column: "filenames", .text)
                t.add(column: "urls", .text)
                t.add(column: "sourceAppId", .text)
                t.add(column: "isPinned", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v3-createSnippetTables") { db in
            try db.create(table: "snippetFolder") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().defaults(to: "Untitled Folder")
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "snippet") { t in
                t.primaryKey("id", .text)
                t.column("folderId", .text)
                    .notNull()
                    .references("snippetFolder", onDelete: .cascade)
                    .indexed()
                t.column("title", .text).notNull().defaults(to: "Untitled Snippet")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v4-createExcludedApp") { db in
            try db.create(table: "excludedApp") { t in
                t.primaryKey("id", .text)
                t.column("bundleId", .text).notNull().unique()
                t.column("appName", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v5-createFTS5") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS clipItemFts
                USING fts5(title, stringValue, content=clipItem, content_rowid=rowid)
                """)

            // Populate FTS index from existing data
            try db.execute(sql: """
                INSERT INTO clipItemFts(clipItemFts) VALUES('rebuild')
                """)
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - ClipItem CRUD

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

            // Rebuild FTS index
            try db.execute(sql: """
                INSERT INTO clipItemFts(clipItemFts) VALUES('rebuild')
                """)
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

    // MARK: - SnippetFolder CRUD

    func fetchFolders() throws -> [SnippetFolder] {
        try dbQueue.read { db in
            try SnippetFolder
                .order(Column("sortIndex").asc)
                .fetchAll(db)
        }
    }

    func saveFolder(_ folder: SnippetFolder) throws {
        try dbQueue.write { db in
            try folder.save(db)
        }
    }

    func deleteFolder(id: String) throws {
        _ = try dbQueue.write { db in
            try SnippetFolder.deleteOne(db, id: id)
        }
    }

    func reorderFolders(_ orderedIds: [String]) throws {
        try dbQueue.write { db in
            for (index, folderId) in orderedIds.enumerated() {
                try db.execute(
                    sql: "UPDATE snippetFolder SET sortIndex = ?, updatedAt = ? WHERE id = ?",
                    arguments: [index, Date(), folderId]
                )
            }
        }
    }

    // MARK: - Snippet CRUD

    func fetchSnippets(inFolder folderId: String) throws -> [Snippet] {
        try dbQueue.read { db in
            try Snippet
                .filter(Column("folderId") == folderId)
                .order(Column("sortIndex").asc)
                .fetchAll(db)
        }
    }

    func saveSnippet(_ snippet: Snippet) throws {
        try dbQueue.write { db in
            try snippet.save(db)
        }
    }

    func deleteSnippet(id: String) throws {
        _ = try dbQueue.write { db in
            try Snippet.deleteOne(db, id: id)
        }
    }

    func moveSnippet(id: String, toFolder folderId: String, atIndex index: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snippet SET folderId = ?, sortIndex = ?, updatedAt = ? WHERE id = ?",
                arguments: [folderId, index, Date(), id]
            )
        }
    }

    // MARK: - Excluded App CRUD

    func fetchExcludedApps() throws -> [ExcludedApp] {
        try dbQueue.read { db in
            try ExcludedApp
                .order(Column("appName").asc)
                .fetchAll(db)
        }
    }

    func addExcludedApp(bundleId: String, appName: String) throws {
        let app = ExcludedApp(bundleId: bundleId, appName: appName)
        try dbQueue.write { db in
            try app.insert(db)
        }
    }

    func removeExcludedApp(id: String) throws {
        _ = try dbQueue.write { db in
            try ExcludedApp.deleteOne(db, id: id)
        }
    }

    func isAppExcluded(bundleId: String) throws -> Bool {
        try dbQueue.read { db in
            try ExcludedApp
                .filter(Column("bundleId") == bundleId)
                .fetchCount(db) > 0
        }
    }

    // MARK: - FTS5 Search

    func searchClips(query: String, limit: Int = 50) throws -> [ClipItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try fetchHistory(limit: limit)
        }

        // Escape special FTS5 characters and add prefix matching
        let sanitized = query
            .replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = "\"\(sanitized)\"*"

        return try dbQueue.read { db in
            try ClipItem.fetchAll(db, sql: """
                SELECT clipItem.* FROM clipItem
                JOIN clipItemFts ON clipItemFts.rowid = clipItem.rowid
                WHERE clipItemFts MATCH ?
                ORDER BY clipItem.updatedAt DESC
                LIMIT ?
                """, arguments: [ftsQuery, limit])
        }
    }

    // MARK: - FTS Index Maintenance

    func updateFTSIndex(for clip: ClipItem) throws {
        try dbQueue.write { db in
            // The content-synced FTS table needs manual updates
            try db.execute(sql: """
                INSERT INTO clipItemFts(clipItemFts) VALUES('rebuild')
                """)
        }
    }
}
