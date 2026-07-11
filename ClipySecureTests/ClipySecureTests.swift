import AppKit
import XCTest
@testable import ClipySecure
import GRDB

final class ClipItemHashTests: XCTestCase {

    func testStringHashStability() {
        let hash1 = ClipItem.computeHash(for: "hello world")
        let hash2 = ClipItem.computeHash(for: "hello world")
        XCTAssertEqual(hash1, hash2)
    }

    func testDifferentStringsProduceDifferentHashes() {
        let hash1 = ClipItem.computeHash(for: "hello")
        let hash2 = ClipItem.computeHash(for: "world")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testEmptyStringHash() {
        let hash = ClipItem.computeHash(for: "")
        XCTAssertFalse(hash.isEmpty)
        XCTAssertEqual(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testHashIsHexEncoded() {
        let hash = ClipItem.computeHash(for: "test")
        XCTAssertEqual(hash.count, 64)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hash.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }
}

final class ClipItemCodableTests: XCTestCase {

    func testTextClipItemRoundTrip() {
        let original = ClipItem(stringValue: "Hello, world!")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        guard let data = try? encoder.encode(original),
              let decoded = try? decoder.decode(ClipItem.self, from: data) else {
            XCTFail("Failed to encode/decode ClipItem")
            return
        }

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.contentHash, original.contentHash)
        XCTAssertEqual(decoded.primaryType, original.primaryType)
        XCTAssertEqual(decoded.isPinned, original.isPinned)
        XCTAssertEqual(decoded.isMemory, original.isMemory)

        // Plaintext content is in-memory only and must never serialize —
        // this is what keeps it out of the database file.
        XCTAssertNil(decoded.stringValue)
        XCTAssertEqual(decoded.title, "")
    }

    func testTypesEncodeDecodeRoundTrip() {
        let types: [ClipContentType] = [.string, .rtf, .url]
        let encoded = ClipItem.encodeTypes(types)
        var item = ClipItem(stringValue: "test")
        item.types = encoded
        let decoded = item.decodedTypes()
        XCTAssertEqual(decoded, types)
    }

    func testStringArrayEncodeDecodeRoundTrip() {
        let original = ["file1.txt", "path/to/file2.png", "special chars: é ñ"]
        let encoded = ClipItem.encodeStringArray(original)
        var item = ClipItem(stringValue: "test")
        item.filenames = encoded
        let decoded = item.decodedFilenames()
        XCTAssertEqual(decoded, original)
    }

    func testEmptyArrayEncode() {
        let encoded = ClipItem.encodeStringArray([])
        XCTAssertEqual(encoded, "[]")
    }
}

final class DatabaseServiceTests: XCTestCase {

    /// Creates a fresh in-memory DatabaseService for each test — no shared state.
    private func makeService() throws -> DatabaseService {
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        return try DatabaseService(dbQueue: dbQueue)
    }

    func testSaveAndFetch() throws {
        let db = try makeService()
        let clip = ClipItem(stringValue: "test save and fetch")
        try db.save(clip: clip)

        let items = try db.fetchHistory(limit: 10)
        XCTAssertTrue(items.contains { $0.id == clip.id })
    }

    func testDuplicateContentUpdatesTimestamp() throws {
        let db = try makeService()
        let clip1 = ClipItem(stringValue: "duplicate test")
        try db.save(clip: clip1)

        let clip2 = ClipItem(stringValue: "duplicate test")
        try db.save(clip: clip2)

        let items = try db.fetchHistory(limit: 100)
        XCTAssertEqual(items.count, 1, "Duplicate content should update existing, not create new row")
    }

    func testDeleteAllPreservesMemory() throws {
        let db = try makeService()
        let clip = ClipItem(stringValue: "memory item")
        try db.save(clip: clip)
        try db.setMemory(clipId: clip.id)

        try db.deleteAll()

        let items = try db.fetchHistory(limit: 100)
        XCTAssertTrue(items.contains { $0.id == clip.id }, "Memory items should survive deleteAll")
    }

    func testDeleteOldestPreservesPinned() throws {
        let db = try makeService()
        for i in 0..<5 {
            var clip = ClipItem(stringValue: "item \(i)")
            clip.isPinned = (i == 0)
            try db.save(clip: clip)
        }

        try db.deleteOldest(keeping: 1)

        let items = try db.fetchHistory(limit: 100)
        let pinned = items.filter(\.isPinned)
        XCTAssertFalse(pinned.isEmpty, "Pinned items should survive deleteOldest")
    }

    func testDeleteOldestPreservesMemory() throws {
        let db = try makeService()
        for i in 0..<5 {
            let clip = ClipItem(stringValue: "item \(i)")
            try db.save(clip: clip)
            if i == 0 {
                try db.setMemory(clipId: clip.id)
            }
        }

        try db.deleteOldest(keeping: 1)

        let items = try db.fetchHistory(limit: 100)
        let memorized = items.filter(\.isMemory)
        XCTAssertFalse(memorized.isEmpty, "Memory items should survive deleteOldest")
    }

    func testFTSSearch() throws {
        let db = try makeService()
        let clip = ClipItem(stringValue: "unique-searchable-token-xyz")
        try db.save(clip: clip)

        let results = try db.searchClips(query: "unique-searchable")
        XCTAssertFalse(results.isEmpty, "FTS search should find the clip")
        XCTAssertTrue(results.contains { $0.id == clip.id })
    }

    func testFetchClipItemById() throws {
        let db = try makeService()
        let clip = ClipItem(stringValue: "fetch by id test")
        try db.save(clip: clip)

        let fetched = try db.fetchClipItem(id: clip.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.stringValue, "fetch by id test")
    }

    func testSnippetFolderCRUD() throws {
        let db = try makeService()
        let folder = SnippetFolder(title: "Test Folder", sortIndex: 0)
        try db.saveFolder(folder)

        let folders = try db.fetchFolders()
        XCTAssertTrue(folders.contains { $0.id == folder.id })

        try db.deleteFolder(id: folder.id)
        let afterDelete = try db.fetchFolders()
        XCTAssertFalse(afterDelete.contains { $0.id == folder.id })
    }

    func testSnippetCRUD() throws {
        let db = try makeService()
        let folder = SnippetFolder(title: "Snippet Test Folder", sortIndex: 0)
        try db.saveFolder(folder)

        let snippet = Snippet(folderId: folder.id, title: "Test Snippet", content: "Hello", sortIndex: 0)
        try db.saveSnippet(snippet)

        let snippets = try db.fetchSnippets(inFolder: folder.id)
        XCTAssertTrue(snippets.contains { $0.id == snippet.id })

        try db.deleteSnippet(id: snippet.id)
        let afterDelete = try db.fetchSnippets(inFolder: folder.id)
        XCTAssertFalse(afterDelete.contains { $0.id == snippet.id })
    }

    func testExcludedAppCRUD() throws {
        let db = try makeService()
        try db.addExcludedApp(bundleId: "com.test.app", appName: "Test App")

        let excluded = try db.isAppExcluded(bundleId: "com.test.app")
        XCTAssertTrue(excluded)

        let apps = try db.fetchExcludedApps()
        guard let app = apps.first(where: { $0.bundleId == "com.test.app" }) else {
            XCTFail("Should find excluded app")
            return
        }

        try db.removeExcludedApp(id: app.id)
        let afterRemove = try db.isAppExcluded(bundleId: "com.test.app")
        XCTAssertFalse(afterRemove)
    }
}

final class SecurityFixTests: XCTestCase {

    func testDuplicatesKeptWhenOverwriteDisabled() throws {
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        let db = try DatabaseService(dbQueue: dbQueue)

        try db.save(clip: ClipItem(stringValue: "same content"), overwriteDuplicates: false)
        try db.save(clip: ClipItem(stringValue: "same content"), overwriteDuplicates: false)

        XCTAssertEqual(try db.fetchHistory(limit: 10).count, 2)
    }

    @MainActor
    func testTransientPasteboardContentIsSkipped() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("normal content", forType: .string)
        XCTAssertNotNil(PasteboardReader.read(from: pasteboard))

        pasteboard.declareTypes([.string, transient], owner: nil)
        pasteboard.setString("transient content", forType: .string)
        XCTAssertNil(PasteboardReader.read(from: pasteboard), "Transient-marked content must never be stored")
    }

    func testEnforceLimitReportsDeletedCount() throws {
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        let db = try DatabaseService(dbQueue: dbQueue)
        let cleanup = DataCleanupService(dbQueue: dbQueue)

        for i in 0..<5 {
            try db.save(clip: ClipItem(stringValue: "item \(i)"))
        }

        XCTAssertEqual(try cleanup.enforceLimit(2), 3)
        XCTAssertEqual(try db.fetchHistory(limit: 10).count, 2)
        XCTAssertEqual(try cleanup.enforceLimit(2), 0)
    }
}

final class FieldEncryptionTests: XCTestCase {

    func testStringRoundTrip() throws {
        let fe = FieldEncryption.ephemeral()
        let ciphertext = try fe.encrypt("sensitive clipboard text")
        XCTAssertEqual(try fe.decryptString(ciphertext), "sensitive clipboard text")
        XCTAssertNil(ciphertext.range(of: Data("sensitive clipboard text".utf8)))
    }

    func testDataRoundTrip() throws {
        let fe = FieldEncryption.ephemeral()
        let blob = Data((0..<1024).map { UInt8($0 % 256) })
        let ciphertext = try fe.encrypt(blob)
        XCTAssertEqual(try fe.decryptData(ciphertext), blob)
    }

    func testDecryptWithWrongKeyThrows() throws {
        let ciphertext = try FieldEncryption.ephemeral().encrypt("secret")
        XCTAssertThrowsError(try FieldEncryption.ephemeral().decryptString(ciphertext))
    }

    func testKeyedHashIsStablePerKeyAndDiffersAcrossKeys() {
        let fe1 = FieldEncryption.ephemeral()
        let fe2 = FieldEncryption.ephemeral()
        let hash = ClipItem.computeHash(for: "hello")
        XCTAssertEqual(fe1.keyedHash(hash), fe1.keyedHash(hash))
        XCTAssertNotEqual(fe1.keyedHash(hash), fe2.keyedHash(hash))
        XCTAssertNotEqual(fe1.keyedHash(hash), hash)
    }
}

final class EncryptionAtRestTests: XCTestCase {

    func testContentIsEncryptedAtRest() throws {
        let fe = FieldEncryption.ephemeral()
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        let db = try DatabaseService(dbQueue: dbQueue, fieldEncryption: fe)

        let clip = ClipItem(stringValue: "super secret plaintext")
        try db.save(clip: clip)

        guard let row = try dbQueue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM clipItem WHERE id = ?", arguments: [clip.id])
        }) else {
            XCTFail("Row not found")
            return
        }

        // Plaintext columns no longer exist in the schema
        XCTAssertFalse(row.columnNames.contains("stringValue"))
        XCTAssertFalse(row.columnNames.contains("title"))

        // Ciphertext does not contain the plaintext bytes
        let encStringValue: Data = row["encStringValue"]
        XCTAssertNil(encStringValue.range(of: Data("super secret plaintext".utf8)))
        XCTAssertEqual(try fe.decryptString(encStringValue), "super secret plaintext")

        // The stored hash is keyed — not the crackable plain SHA-256
        let storedHash: String = row["contentHash"]
        XCTAssertEqual(storedHash, fe.keyedHash(clip.contentHash))
        XCTAssertNotEqual(storedHash, clip.contentHash)
    }

    func testSearchIndexNotOnDisk() throws {
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        let db = try DatabaseService(dbQueue: dbQueue)
        try db.save(clip: ClipItem(stringValue: "findable text"))

        // The FTS index (and its shadow tables) must not exist in the main
        // database — searchable plaintext lives only in the attached memory db.
        let ftsTableCount = try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM main.sqlite_master WHERE name LIKE 'clipItemFts%'"
            ) ?? -1
        }
        XCTAssertEqual(ftsTableCount, 0)

        // Search still works via the in-memory index
        let results = try db.searchClips(query: "findable")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.stringValue, "findable text")
    }

    func testSearchIndexRebuiltForNewServiceInstance() throws {
        let fe = FieldEncryption.ephemeral()
        let dbQueue = try DatabaseQueue(configuration: Configuration())

        let db1 = try DatabaseService(dbQueue: dbQueue, fieldEncryption: fe)
        try db1.save(clip: ClipItem(stringValue: "persistent searchable clip"))

        // A second service on the same database (fresh launch) must rebuild
        // the in-memory search index from the encrypted rows.
        let db2 = try DatabaseService(dbQueue: dbQueue, fieldEncryption: fe)
        let results = try db2.searchClips(query: "persistent")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.stringValue, "persistent searchable clip")
    }

    func testWrongKeyDegradesGracefully() throws {
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        let db1 = try DatabaseService(dbQueue: dbQueue, fieldEncryption: .ephemeral())
        try db1.save(clip: ClipItem(stringValue: "unreadable later"))

        // Same database, different key (e.g. Keychain entry lost):
        // items surface with empty content instead of crashing or throwing.
        let db2 = try DatabaseService(dbQueue: dbQueue, fieldEncryption: .ephemeral())
        let items = try db2.fetchHistory(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "")
        XCTAssertNil(items.first?.stringValue)
    }

    func testMigrationEncryptsExistingPlaintextRows() throws {
        let fe = FieldEncryption.ephemeral()
        let dbQueue = try DatabaseQueue(configuration: Configuration())

        // Build a pre-encryption (v9) database with a plaintext row,
        // exactly as it would exist on disk before the upgrade.
        let migrator = DatabaseService.makeMigrator(fieldEncryption: fe)
        try migrator.migrate(dbQueue, upTo: "v9-addUpdatedAtIndex")

        let legacyHash = ClipItem.computeHash(for: "legacy secret")
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipItem
                        (id, contentHash, title, primaryType, stringValue, createdAt, updatedAt, isPinned, isMemory)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0)
                    """,
                arguments: ["legacy-1", legacyHash, "legacy secret", "string", "legacy secret", Date(), Date()]
            )
            try db.execute(
                sql: "INSERT INTO clipItemFts(clipId, title, stringValue) VALUES (?, ?, ?)",
                arguments: ["legacy-1", "legacy secret", "legacy secret"]
            )
        }

        // Constructing the service runs v10 and rebuilds the search index
        let db = try DatabaseService(dbQueue: dbQueue, fieldEncryption: fe)

        let items = try db.fetchHistory(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "legacy secret")
        XCTAssertEqual(items.first?.stringValue, "legacy secret")

        guard let row = try dbQueue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM clipItem WHERE id = 'legacy-1'")
        }) else {
            XCTFail("Row not found")
            return
        }
        XCTAssertFalse(row.columnNames.contains("stringValue"))
        XCTAssertEqual(row["contentHash"] as String, fe.keyedHash(legacyHash))

        // Old plaintext FTS table is gone; search works via the memory index
        let ftsTableCount = try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM main.sqlite_master WHERE name LIKE 'clipItemFts%'"
            ) ?? -1
        }
        XCTAssertEqual(ftsTableCount, 0)
        XCTAssertEqual(try db.searchClips(query: "legacy").count, 1)

        // Post-migration dedup still matches the same content
        try db.save(clip: ClipItem(stringValue: "legacy secret"))
        XCTAssertEqual(try db.fetchHistory(limit: 10).count, 1)
    }
}

final class ImportDeduplicationTests: XCTestCase {

    private func makeDbQueue() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        let db = try DatabaseService(dbQueue: dbQueue)
        _ = db // ensure migrations run
        return dbQueue
    }

    private func makeXML(folders: [(title: String, snippets: [(title: String, content: String)])]) -> URL {
        var xml = "<folders>"
        for folder in folders {
            xml += "<folder><title>\(folder.title)</title><snippets>"
            for snippet in folder.snippets {
                xml += "<snippet><title>\(snippet.title)</title><content>\(snippet.content)</content></snippet>"
            }
            xml += "</snippets></folder>"
        }
        xml += "</folders>"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-import-\(UUID().uuidString).xml")
        try! xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testRepeatedImportDoesNotDuplicate() throws {
        let dbQueue = try makeDbQueue()
        let url = makeXML(folders: [
            (title: "Work", snippets: [
                (title: "Email", content: "Dear Sir"),
                (title: "Sign-off", content: "Regards"),
            ]),
        ])

        try SnippetImportExport.importXML(from: url, into: dbQueue)
        try SnippetImportExport.importXML(from: url, into: dbQueue)

        let folders = try dbQueue.read { db in try SnippetFolder.fetchAll(db) }
        XCTAssertEqual(folders.filter { $0.title == "Work" }.count, 1, "Should reuse existing folder")

        let snippets = try dbQueue.read { db in try Snippet.fetchAll(db) }
        XCTAssertEqual(snippets.count, 2, "Should not create duplicate snippets")

        try? FileManager.default.removeItem(at: url)
    }

    func testImportNewSnippetIntoExistingFolder() throws {
        let dbQueue = try makeDbQueue()
        let url1 = makeXML(folders: [
            (title: "Work", snippets: [(title: "Email", content: "Dear Sir")]),
        ])
        let url2 = makeXML(folders: [
            (title: "Work", snippets: [(title: "Memo", content: "To all staff")]),
        ])

        try SnippetImportExport.importXML(from: url1, into: dbQueue)
        try SnippetImportExport.importXML(from: url2, into: dbQueue)

        let folders = try dbQueue.read { db in try SnippetFolder.fetchAll(db) }
        XCTAssertEqual(folders.filter { $0.title == "Work" }.count, 1)

        let snippets = try dbQueue.read { db in try Snippet.fetchAll(db) }
        XCTAssertEqual(snippets.count, 2, "Should add the new snippet without duplicating the old one")

        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }
}

final class StringTruncateTests: XCTestCase {

    func testShortStringNotTruncated() {
        let short = "hello"
        XCTAssertEqual(short.truncated(to: 10), "hello")
    }

    func testLongStringTruncated() {
        let long = String(repeating: "a", count: 100)
        let result = long.truncated(to: 10)
        XCTAssertEqual(result.count, 11) // 10 chars + ellipsis
        XCTAssertTrue(result.hasSuffix("\u{2026}"))
    }
}
