import Foundation
import GRDB
import OSLog

final class DatabaseService: Sendable {
    let dbQueue: DatabaseQueue
    private let fieldEncryption: FieldEncryption

    init() throws {
        let appSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.appSupportDirectoryName)

        try FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        // Restrict directory permissions to owner only (700)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: appSupportURL.path
        )

        let dbPath = appSupportURL.appendingPathComponent("clipy.db").path

        // Sensitive content is encrypted field-by-field with AES-GCM before it
        // reaches SQLite (see FieldEncryption). Full-database SQLCipher remains
        // an option once GRDB ships native package-trait support.
        fieldEncryption = try FieldEncryption(keyManager: EncryptionKeyManager())
        dbQueue = try DatabaseQueue(path: dbPath)
        try Self.setupDatabase(dbQueue, fieldEncryption: fieldEncryption)
    }

    /// Test-only initializer using an in-memory database and an ephemeral
    /// encryption key that never touches the Keychain.
    convenience init(dbQueue: DatabaseQueue) throws {
        try self.init(dbQueue: dbQueue, fieldEncryption: .ephemeral())
    }

    /// Test-only initializer that also takes the encryption key, so tests can
    /// share a key across service instances on the same database.
    init(dbQueue: DatabaseQueue, fieldEncryption: FieldEncryption) throws {
        self.dbQueue = dbQueue
        self.fieldEncryption = fieldEncryption
        try Self.setupDatabase(dbQueue, fieldEncryption: fieldEncryption)
    }

    private static func setupDatabase(_ dbQueue: DatabaseQueue, fieldEncryption: FieldEncryption) throws {
        let migrator = makeMigrator(fieldEncryption: fieldEncryption)

        // When migrations are pending, VACUUM afterwards: v10 rewrites plaintext
        // content into encrypted columns, and VACUUM overwrites the freed pages
        // so the old plaintext cannot be recovered from the file.
        let hadPendingMigrations = try dbQueue.read { db in
            try !migrator.hasCompletedMigrations(db)
        }
        try migrator.migrate(dbQueue)
        if hadPendingMigrations {
            try dbQueue.vacuum()
        }

        try setupSearchIndex(dbQueue, fieldEncryption: fieldEncryption)
    }

    static func makeMigrator(fieldEncryption: FieldEncryption) -> DatabaseMigrator {
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
            // Original content-synced FTS5 — broken with text PKs, replaced by v6
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS clipItemFts
                USING fts5(title, stringValue, content=clipItem, content_rowid=rowid)
                """)
        }

        migrator.registerMigration("v6-fixFTS5Standalone") { db in
            // Drop the broken content-synced FTS table
            try db.execute(sql: "DROP TABLE IF EXISTS clipItemFts")

            // Create standalone FTS5 table with clipId for joining
            try db.execute(sql: """
                CREATE VIRTUAL TABLE clipItemFts
                USING fts5(clipId UNINDEXED, title, stringValue)
                """)

            // Populate from existing data
            try db.execute(sql: """
                INSERT INTO clipItemFts(clipId, title, stringValue)
                SELECT id, title, COALESCE(stringValue, '') FROM clipItem
                """)
        }

        migrator.registerMigration("v7-snippetOptionalFolder") { db in
            // Recreate snippet table with optional folderId to allow root-level snippets.
            // SQLite doesn't support ALTER COLUMN, so we recreate the table.
            // Drop the existing index first — renaming the table doesn't rename its indexes,
            // so the new table's .indexed() would collide with the old index name.
            try db.execute(sql: "DROP INDEX IF EXISTS snippet_on_folderId")
            try db.rename(table: "snippet", to: "snippet_old")

            try db.create(table: "snippet") { t in
                t.primaryKey("id", .text)
                t.column("folderId", .text)
                    .references("snippetFolder", onDelete: .cascade)
                    .indexed()
                t.column("title", .text).notNull().defaults(to: "Untitled Snippet")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.execute(sql: """
                INSERT INTO snippet (id, folderId, title, content, sortIndex, isEnabled, createdAt, updatedAt)
                SELECT id, folderId, title, content, sortIndex, isEnabled, createdAt, updatedAt
                FROM snippet_old
                """)

            try db.drop(table: "snippet_old")
        }

        migrator.registerMigration("v8-addMemoryColumns") { db in
            try db.alter(table: "clipItem") { t in
                t.add(column: "isMemory", .boolean).notNull().defaults(to: false)
                t.add(column: "memorizedAt", .datetime)
            }
        }

        migrator.registerMigration("v9-addUpdatedAtIndex") { db in
            try db.create(
                index: "clipItem_on_updatedAt",
                on: "clipItem",
                columns: ["updatedAt"]
            )
        }

        migrator.registerMigration("v10-encryptClipContent") { db in
            try db.alter(table: "clipItem") { t in
                t.add(column: "encTitle", .blob)
                t.add(column: "encStringValue", .blob)
                t.add(column: "encRtfData", .blob)
                t.add(column: "encPdfData", .blob)
                t.add(column: "encImageData", .blob)
                t.add(column: "encFilenames", .blob)
                t.add(column: "encUrls", .blob)
            }

            // Encrypt every existing row's content, and replace the plain
            // SHA-256 contentHash with a keyed hash so the file cannot be used
            // to confirm or crack clipboard content offline.
            let ids = try String.fetchAll(db, sql: "SELECT id FROM clipItem")
            for id in ids {
                guard let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT contentHash, title, stringValue, rtfData, pdfData,
                               imageData, filenames, urls
                        FROM clipItem WHERE id = ?
                        """,
                    arguments: [id]
                ) else { continue }

                let title: String = row["title"]
                let stringValue: String? = row["stringValue"]
                let rtfData: Data? = row["rtfData"]
                let pdfData: Data? = row["pdfData"]
                let imageData: Data? = row["imageData"]
                let filenames: String? = row["filenames"]
                let urls: String? = row["urls"]
                let contentHash: String = row["contentHash"]

                try db.execute(
                    sql: """
                        UPDATE clipItem SET
                            contentHash = ?,
                            encTitle = ?,
                            encStringValue = ?,
                            encRtfData = ?,
                            encPdfData = ?,
                            encImageData = ?,
                            encFilenames = ?,
                            encUrls = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        fieldEncryption.keyedHash(contentHash),
                        try fieldEncryption.encrypt(title),
                        try stringValue.map { try fieldEncryption.encrypt($0) },
                        try rtfData.map { try fieldEncryption.encrypt($0) },
                        try pdfData.map { try fieldEncryption.encrypt($0) },
                        try imageData.map { try fieldEncryption.encrypt($0) },
                        try filenames.map { try fieldEncryption.encrypt($0) },
                        try urls.map { try fieldEncryption.encrypt($0) },
                        id,
                    ]
                )
            }

            // Drop the plaintext columns entirely — content can no longer be
            // written to disk unencrypted, even by accident.
            try db.alter(table: "clipItem") { t in
                t.drop(column: "title")
                t.drop(column: "stringValue")
                t.drop(column: "rtfData")
                t.drop(column: "pdfData")
                t.drop(column: "imageData")
                t.drop(column: "filenames")
                t.drop(column: "urls")
            }

            // The on-disk FTS index holds plaintext content. The search index
            // now lives in an attached in-memory database (see setupSearchIndex).
            try db.execute(sql: "DROP TABLE IF EXISTS clipItemFts")
        }

        return migrator
    }

    /// FTS5 needs plaintext to tokenize, so the search index lives in an
    /// attached in-memory database that is rebuilt at launch — searchable text
    /// never reaches disk. DatabaseQueue uses a single connection, so the
    /// attachment persists for the whole app session.
    private static func setupSearchIndex(_ dbQueue: DatabaseQueue, fieldEncryption: FieldEncryption) throws {
        let isAttached = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA database_list")
                .contains { ($0["name"] as String?) == "ftsmem" }
        }
        if !isAttached {
            // ATTACH cannot run inside a transaction.
            try dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "ATTACH DATABASE ':memory:' AS ftsmem")
            }
        }

        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS ftsmem.clipItemFts")
            try db.execute(sql: """
                CREATE VIRTUAL TABLE ftsmem.clipItemFts
                USING fts5(clipId UNINDEXED, title, stringValue)
                """)

            let cursor = try Row.fetchCursor(
                db,
                sql: "SELECT id, encTitle, encStringValue FROM clipItem"
            )
            while let row = try cursor.next() {
                let id: String = row["id"]
                var title = ""
                var stringValue = ""
                do {
                    if let enc = row["encTitle"] as Data? {
                        title = try fieldEncryption.decryptString(enc)
                    }
                    if let enc = row["encStringValue"] as Data? {
                        stringValue = try fieldEncryption.decryptString(enc)
                    }
                } catch {
                    Logger.database.error("Failed to decrypt clip for search indexing: \(error.localizedDescription)")
                }
                try db.execute(
                    sql: "INSERT INTO ftsmem.clipItemFts(clipId, title, stringValue) VALUES (?, ?, ?)",
                    arguments: [id, title, stringValue]
                )
            }
        }
    }

    // MARK: - Encryption

    /// Returns a copy with content encrypted into the enc* columns and the
    /// contentHash keyed. Every ClipItem write goes through this.
    private func encryptForStorage(_ clip: ClipItem) throws -> ClipItem {
        var stored = clip
        stored.contentHash = fieldEncryption.keyedHash(clip.contentHash)
        stored.encTitle = try fieldEncryption.encrypt(clip.title)
        stored.encStringValue = try clip.stringValue.map { try fieldEncryption.encrypt($0) }
        stored.encRtfData = try clip.rtfData.map { try fieldEncryption.encrypt($0) }
        stored.encPdfData = try clip.pdfData.map { try fieldEncryption.encrypt($0) }
        stored.encImageData = try clip.imageData.map { try fieldEncryption.encrypt($0) }
        stored.encFilenames = try clip.filenames.map { try fieldEncryption.encrypt($0) }
        stored.encUrls = try clip.urls.map { try fieldEncryption.encrypt($0) }
        return stored
    }

    /// Populates the in-memory plaintext fields from the enc* columns.
    /// Tolerant of per-item failures (logged): a clip that cannot be decrypted
    /// shows up with empty content rather than breaking the whole list.
    func decrypt(_ clip: ClipItem) -> ClipItem {
        var item = clip
        do {
            if let enc = clip.encTitle {
                item.title = try fieldEncryption.decryptString(enc)
            }
            if let enc = clip.encStringValue {
                item.stringValue = try fieldEncryption.decryptString(enc)
            }
            if let enc = clip.encRtfData {
                item.rtfData = try fieldEncryption.decryptData(enc)
            }
            if let enc = clip.encPdfData {
                item.pdfData = try fieldEncryption.decryptData(enc)
            }
            if let enc = clip.encImageData {
                item.imageData = try fieldEncryption.decryptData(enc)
            }
            if let enc = clip.encFilenames {
                item.filenames = try fieldEncryption.decryptString(enc)
            }
            if let enc = clip.encUrls {
                item.urls = try fieldEncryption.decryptString(enc)
            }
        } catch {
            Logger.database.error("Failed to decrypt clip: \(error.localizedDescription)")
        }
        return item
    }

    func decrypt(_ clips: [ClipItem]) -> [ClipItem] {
        clips.map { decrypt($0) }
    }

    /// Columns to select when we only need metadata (no blobs).
    /// Used by observations and menu rendering to avoid loading images/RTF/PDF.
    static let lightweightColumns = [
        Column("id"), Column("contentHash"), Column("primaryType"),
        Column("createdAt"), Column("updatedAt"),
        Column("types"), Column("sourceAppId"),
        Column("isPinned"), Column("isMemory"), Column("memorizedAt"),
        Column("encTitle"), Column("encStringValue"),
        Column("encFilenames"), Column("encUrls"),
    ]

    /// Fetch a single full ClipItem by id (including blobs), for paste time.
    func fetchClipItem(id: String) throws -> ClipItem? {
        let row = try dbQueue.read { db in
            try ClipItem.fetchOne(db, id: id)
        }
        return row.map { decrypt($0) }
    }

    // MARK: - ClipItem CRUD

    /// Expects a freshly created ClipItem whose contentHash is the plain
    /// creation-time SHA-256; the stored hash is keyed by encryptForStorage.
    /// To reorder an existing clip, use touch(clipId:) instead.
    /// When overwriteDuplicates is false, identical content is stored as a
    /// new entry instead of bumping the existing one.
    func save(clip: ClipItem, overwriteDuplicates: Bool = true) throws {
        let stored = try encryptForStorage(clip)
        try dbQueue.write { db in
            if overwriteDuplicates,
               var existing = try ClipItem
                   .filter(Column("contentHash") == stored.contentHash)
                   .fetchOne(db)
            {
                // Content is unchanged, so its search index entry stays valid.
                existing.updatedAt = Date()
                try existing.update(db)
            } else {
                try stored.insert(db)

                // Add search index entry (in-memory only, never on disk)
                try db.execute(
                    sql: "INSERT INTO ftsmem.clipItemFts(clipId, title, stringValue) VALUES (?, ?, ?)",
                    arguments: [stored.id, clip.title, clip.stringValue ?? ""]
                )
            }
        }
    }

    /// Bumps a clip's updatedAt so it moves to the top of history.
    func touch(clipId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipItem SET updatedAt = ? WHERE id = ?",
                arguments: [Date(), clipId]
            )
        }
    }

    func fetchHistory(limit: Int = Constants.defaultHistoryLimit) throws -> [ClipItem] {
        let rows = try dbQueue.read { db in
            try ClipItem
                .order(Column("updatedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return decrypt(rows)
    }

    func deleteAll() throws {
        try dbQueue.write { db in
            // Preserve memory items
            try db.execute(sql: """
                DELETE FROM ftsmem.clipItemFts WHERE clipId IN (
                    SELECT id FROM clipItem WHERE isMemory = 0
                )
                """)
            try db.execute(sql: "DELETE FROM clipItem WHERE isMemory = 0")
        }
        try dbQueue.vacuum()
    }

    func deleteOldest(keeping limit: Int) throws {
        try dbQueue.write { db in
            // Clean up FTS entries for clips about to be deleted, preserving pinned/memory items
            try db.execute(
                sql: """
                    DELETE FROM ftsmem.clipItemFts WHERE clipId IN (
                        SELECT id FROM clipItem
                        WHERE isPinned = 0 AND isMemory = 0
                        AND id NOT IN (
                            SELECT id FROM clipItem
                            WHERE isPinned = 0 AND isMemory = 0
                            ORDER BY updatedAt DESC LIMIT ?
                        )
                    )
                    """,
                arguments: [limit]
            )
            try db.execute(
                sql: """
                    DELETE FROM clipItem
                    WHERE isPinned = 0 AND isMemory = 0
                    AND id NOT IN (
                        SELECT id FROM clipItem
                        WHERE isPinned = 0 AND isMemory = 0
                        ORDER BY updatedAt DESC LIMIT ?
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

    func fetchRootSnippets() throws -> [Snippet] {
        try dbQueue.read { db in
            try Snippet
                .filter(Column("folderId") == nil)
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

    func moveSnippet(id: String, toFolder folderId: String?, atIndex index: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snippet SET folderId = ?, sortIndex = ?, updatedAt = ? WHERE id = ?",
                arguments: [folderId, index, Date(), id]
            )
        }
    }

    // MARK: - Memory CRUD

    func setMemory(clipId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipItem SET isMemory = 1, memorizedAt = ? WHERE id = ?",
                arguments: [Date(), clipId]
            )
        }
    }

    func removeFromMemory(clipId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipItem SET isMemory = 0, memorizedAt = NULL WHERE id = ?",
                arguments: [clipId]
            )
        }
    }

    func promoteToSnippet(clipItem: ClipItem, folderId: String?, sortIndex: Int) throws {
        let snippet = Snippet(
            folderId: folderId,
            title: clipItem.title,
            content: clipItem.stringValue ?? clipItem.title,
            sortIndex: sortIndex
        )
        try dbQueue.write { db in
            try snippet.insert(db)
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

        let rows = try dbQueue.read { db in
            try ClipItem.fetchAll(db, sql: """
                SELECT clipItem.* FROM clipItem
                JOIN ftsmem.clipItemFts AS fts ON fts.clipId = clipItem.id
                WHERE fts.clipItemFts MATCH ?
                ORDER BY clipItem.updatedAt DESC
                LIMIT ?
                """, arguments: [ftsQuery, limit])
        }
        return decrypt(rows)
    }

}
