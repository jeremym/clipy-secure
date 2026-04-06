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
        XCTAssertEqual(decoded.stringValue, original.stringValue)
        XCTAssertEqual(decoded.contentHash, original.contentHash)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.primaryType, original.primaryType)
        XCTAssertEqual(decoded.isPinned, original.isPinned)
        XCTAssertEqual(decoded.isMemory, original.isMemory)
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
        let matching = items.filter { $0.contentHash == clip1.contentHash }
        XCTAssertEqual(matching.count, 1, "Duplicate content should update existing, not create new row")
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
