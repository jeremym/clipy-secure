import AppKit
import Defaults
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

final class MenuShortcutKeysTests: XCTestCase {

    func testDefaultLeadsWithDigits() {
        let keys = MenuShortcutKeys.normalized(MenuShortcutKeys.default)
        XCTAssertEqual(keys.prefix(5).map(String.init), ["1", "2", "3", "4", "5"])
        // Inline 1–5 then the first folder key is the sixth slot.
        XCTAssertEqual(MenuShortcutKeys.key(at: 5, in: keys), "6")
    }

    func testNormalizeStripsWhitespaceLowercasesAndDedupes() {
        let keys = MenuShortcutKeys.normalized(" 1 2  a A b 1 ")
        XCTAssertEqual(keys.map(String.init), ["1", "2", "a", "b"])
    }

    func testKeyOutOfRangeIsEmpty() {
        let keys = MenuShortcutKeys.normalized("12")
        XCTAssertEqual(MenuShortcutKeys.key(at: 0, in: keys), "1")
        XCTAssertEqual(MenuShortcutKeys.key(at: 2, in: keys), "")
        XCTAssertEqual(MenuShortcutKeys.key(at: -1, in: keys), "")
    }

    func testCustomSequenceOmittingDigitsFreesThem() {
        // A user who drops "1" and "2" so those keys are free for type-jumping
        // to snippet folders named like "1Password".
        let keys = MenuShortcutKeys.normalized("34567890")
        XCTAssertEqual(MenuShortcutKeys.key(at: 0, in: keys), "3")
        XCTAssertFalse(keys.contains("1"))
        XCTAssertFalse(keys.contains("2"))
    }

    // MARK: - Shared-sequence continuation (review #6)

    func testTopLevelSlotsInlinePlusFolders() {
        // 5 inline + ceil(27 / 10) = 3 folders → 8 slots, so the memory section
        // begins keying its rows at index 8.
        XCTAssertEqual(MenuShortcutKeys.topLevelSlots(itemCount: 32, inlineCount: 5, folderSize: 10), 8)
    }

    func testTopLevelSlotsAllInlineWhenZero() {
        // History's convention: 0 inline means every row is inline.
        XCTAssertEqual(MenuShortcutKeys.topLevelSlots(itemCount: 7, inlineCount: 0, folderSize: 10), 7)
    }

    func testTopLevelSlotsNoOverflow() {
        XCTAssertEqual(MenuShortcutKeys.topLevelSlots(itemCount: 3, inlineCount: 5, folderSize: 10), 3)
    }

    func testTopLevelSlotsEmptySectionConsumesNothing() {
        XCTAssertEqual(MenuShortcutKeys.topLevelSlots(itemCount: 0, inlineCount: 5, folderSize: 10), 0)
    }

    func testTopLevelSlotsExactFolderBoundary() {
        // 5 inline + exactly 10 remaining → 1 folder, not 2.
        XCTAssertEqual(MenuShortcutKeys.topLevelSlots(itemCount: 15, inlineCount: 5, folderSize: 10), 6)
    }
}

/// White-box tests that the menu builder assigns real single-key shortcuts to
/// memory rows and continues the shared sequence past the history section
/// (review #6). Key assignments ride on each item's `identifier` as
/// "clipkey:<key>" (see `MenuKeyRouter.assign`).
final class MemoryMenuKeyTests: XCTestCase {

    private let keyPrefix = "clipkey:"
    private var saved: [String: Any?] = [:]

    @MainActor
    private func withMenuDefaults(_ body: () -> Void) {
        // Snapshot and restore the UserDefaults keys the builder reads, so the
        // test never leaves the developer's real preferences changed.
        let keys = [
            "menuShortcutKeys", "maxHistorySize", "numberOfItemsInline",
            "numberOfItemsInFolder", "maxMemorySize", "numberOfMemoryItemsInline",
            "numberOfItemsPerMemoryFolder", "menuItemTitleMaxLength",
            "showImagesInMenu", "showTooltips",
        ]
        let defaults = UserDefaults.standard
        for key in keys { saved[key] = defaults.object(forKey: key) }
        defer {
            for key in keys {
                if let value = saved[key], value != nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        Defaults[.menuShortcutKeys] = MenuShortcutKeys.default // 1234567890abc…
        Defaults[.maxHistorySize] = 32
        Defaults[.numberOfItemsInline] = 5
        Defaults[.numberOfItemsInFolder] = 10
        Defaults[.maxMemorySize] = 100
        Defaults[.menuItemTitleMaxLength] = 40
        Defaults[.showImagesInMenu] = false
        Defaults[.showTooltips] = false
        body()
    }

    private func items(_ count: Int) -> [ClipItem] {
        (0..<count).map { ClipItem(stringValue: "clip \($0)") }
    }

    @MainActor
    func testHistoryReturnsNextFreeKeyIndex() {
        withMenuDefaults {
            let menu = NSMenu()
            let next = ClipMenuBuilder.addHistoryItems(
                to: menu,
                items: items(32),
                target: NSObject(),
                pasteAction: Selector(("noop:")),
                memoryAction: Selector(("noop:")),
                folderAction: Selector(("noop:"))
            )
            // 5 inline + 3 folders of 10 = 8.
            XCTAssertEqual(next, 8)
        }
    }

    @MainActor
    func testMemoryInlineRowsContinueSequenceAfterHistory() {
        withMenuDefaults {
            Defaults[.numberOfMemoryItemsInline] = 2
            Defaults[.numberOfItemsPerMemoryFolder] = 40

            let menu = NSMenu()
            // History consumes slots 0–7, so memory starts at index 8 → "9","0".
            ClipMenuBuilder.addMemoryItems(
                to: menu,
                items: items(5),
                startingKeyIndex: 8,
                target: NSObject(),
                pasteAction: Selector(("noop:")),
                promoteAction: Selector(("noop:")),
                folderAction: Selector(("noop:"))
            )

            // items[0] is the "Memory" header; inline base rows follow, each
            // trailed by its ⌥ alternate (which carries no key of its own).
            XCTAssertEqual(menu.items[1].identifier?.rawValue, keyPrefix + "9")
            XCTAssertEqual(menu.items[3].identifier?.rawValue, keyPrefix + "0")
        }
    }

    @MainActor
    func testMemoryZeroInlineCollapsesToSubmenu() {
        withMenuDefaults {
            Defaults[.numberOfMemoryItemsInline] = 0
            Defaults[.numberOfItemsPerMemoryFolder] = 40

            let menu = NSMenu()
            ClipMenuBuilder.addMemoryItems(
                to: menu,
                items: items(5),
                startingKeyIndex: 8,
                target: NSObject(),
                pasteAction: Selector(("noop:")),
                promoteAction: Selector(("noop:")),
                folderAction: Selector(("noop:"))
            )

            // header, then the single Memory ▸ submenu row (no inline rows).
            let submenuRow = menu.items.first { $0.submenu != nil }
            XCTAssertNotNil(submenuRow, "0 inline should collapse to one Memory submenu")
            // Rows inside restart the sequence at the head: first row is "1".
            XCTAssertEqual(submenuRow?.submenu?.items.first?.identifier?.rawValue, keyPrefix + "1")
        }
    }
}

/// Image storage (review #4): full-resolution bytes for faithful paste, a small
/// thumbnail for display.
final class ImageStorageTests: XCTestCase {

    /// Builds a solid-colour image at a known pixel size without lockFocus
    /// (forbidden per project rules).
    private func makeImage(width: Int, height: Int) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func pixelWidth(ofPNG data: Data) -> Int? {
        NSBitmapImageRep(data: data)?.pixelsWide
    }

    func testPNGDataPreservesFullResolution() throws {
        let image = makeImage(width: 800, height: 600)
        let png = try XCTUnwrap(image.pngData())
        XCTAssertEqual(pixelWidth(ofPNG: png), 800, "full image keeps its resolution")
    }

    func testThumbnailShrinksLargeImages() throws {
        let image = makeImage(width: 800, height: 600)
        let thumb = try XCTUnwrap(image.resizedToThumbnail(maxWidth: 200))
        XCTAssertEqual(pixelWidth(ofPNG: thumb), 200, "thumbnail is capped at maxWidth")
        XCTAssertLessThan(thumb.count, try XCTUnwrap(image.pngData()).count, "thumbnail is smaller than the full image")
    }
}

/// Snippet editor selection model (review #12/#13, plan §4). UI (highlight,
/// focus, sidebar width) is manually verified; this covers the view-model logic.
@MainActor
final class SnippetSelectionTests: XCTestCase {

    private func makeViewModel() throws -> (SnippetEditorViewModel, DatabaseService) {
        let db = try DatabaseService(dbQueue: DatabaseQueue(configuration: Configuration()))
        return (SnippetEditorViewModel(databaseService: db), db)
    }

    func testSelectionDerivesLegacyAccessors() throws {
        let (vm, _) = try makeViewModel()

        vm.selection = .snippet("s1")
        XCTAssertEqual(vm.selectedSnippetId, "s1")
        XCTAssertNil(vm.selectedFolderId)
        XCTAssertFalse(vm.isRootSelected)

        vm.selection = .folder("f1")
        XCTAssertEqual(vm.selectedFolderId, "f1")
        XCTAssertNil(vm.selectedSnippetId)
        XCTAssertFalse(vm.isRootSelected)

        vm.selection = .root
        XCTAssertTrue(vm.isRootSelected)
        XCTAssertNil(vm.selectedFolderId)
        XCTAssertNil(vm.selectedSnippetId)
    }

    func testAddSnippetIntoSelectedFolder() throws {
        let (vm, db) = try makeViewModel()
        let folder = SnippetFolder(title: "Work", sortIndex: 0)
        try db.saveFolder(folder)
        vm.selection = .folder(folder.id)

        vm.addSnippet()

        let saved = try db.fetchSnippets(inFolder: folder.id)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(vm.selectedSnippetId, saved.first?.id, "the new snippet becomes selected")
    }

    func testAddSnippetWithNoSelectionAndNoFoldersCreatesMySnippets() throws {
        let (vm, db) = try makeViewModel()
        vm.selection = nil

        vm.addSnippet()

        let folders = try db.fetchFolders()
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.title, "My Snippets")
        let saved = try db.fetchSnippets(inFolder: folders[0].id)
        XCTAssertEqual(saved.count, 1, "snippet should land in the new folder, not at the root")
    }

    func testFolderHasSnippets() throws {
        let (vm, db) = try makeViewModel()
        let folder = SnippetFolder(title: "F", sortIndex: 0)
        try db.saveFolder(folder)
        // `allSnippets` is normally filled by the async observation; set it
        // directly for a deterministic check.
        vm.allSnippets = [Snippet(folderId: folder.id, title: "x", sortIndex: 0)]
        XCTAssertTrue(vm.folderHasSnippets(folder.id))
        XCTAssertFalse(vm.folderHasSnippets("other"))
    }

    func testDeleteFolderClearsSelection() throws {
        let (vm, db) = try makeViewModel()
        let folder = SnippetFolder(title: "F", sortIndex: 0)
        try db.saveFolder(folder)
        vm.selection = .folder(folder.id)

        vm.deleteFolder(folder.id)

        XCTAssertNil(vm.selection)
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

    func testDeleteClipRemovesRowAndSearchIndex() throws {
        let db = try makeService()
        let clip = ClipItem(stringValue: "delete-me-token")
        try db.save(clip: clip)
        XCTAssertNotNil(try db.fetchClipItem(id: clip.id))
        XCTAssertFalse(try db.searchClips(query: "delete-me-token").isEmpty)

        try db.deleteClip(id: clip.id)

        XCTAssertNil(try db.fetchClipItem(id: clip.id))
        XCTAssertTrue(try db.searchClips(query: "delete-me-token").isEmpty, "the FTS row must go too")
    }

    func testDeleteClipRemovesMemorizedClip() throws {
        // The security gap in review #2: a memorised secret had no removal path.
        let db = try makeService()
        let clip = ClipItem(stringValue: "secret-memory")
        try db.save(clip: clip)
        try db.setMemory(clipId: clip.id)

        try db.deleteClip(id: clip.id)

        XCTAssertNil(try db.fetchClipItem(id: clip.id))
    }

    func testImageClipStoresFullBytesAndThumbnailSeparately() throws {
        // review #4: the full image and its display thumbnail are distinct
        // encrypted columns and both survive a round trip.
        let db = try makeService()
        let full = Data(repeating: 0xAB, count: 4096)
        let thumb = Data(repeating: 0xCD, count: 256)
        let content = ClipContent(
            primaryType: .tiff, stringValue: nil, rtfData: nil, pdfData: nil,
            imageData: full, thumbnailData: thumb, filenames: nil, urls: nil,
            sourceAppId: nil, types: [.tiff]
        )
        let clip = ClipItem(content: content)
        try db.save(clip: clip)

        let fetched = try db.fetchClipItem(id: clip.id)
        XCTAssertEqual(fetched?.imageData, full, "full image bytes must survive")
        XCTAssertEqual(fetched?.thumbnailData, thumb, "the separate thumbnail must survive")
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

    func testReorderSnippetsWithinFolderInBothDirections() throws {
        let db = try makeService()
        let folder = SnippetFolder(title: "Reorder", sortIndex: 0)
        try db.saveFolder(folder)

        let first = Snippet(folderId: folder.id, title: "First", sortIndex: 0)
        let second = Snippet(folderId: folder.id, title: "Second", sortIndex: 1)
        let third = Snippet(folderId: folder.id, title: "Third", sortIndex: 2)
        try db.saveSnippet(first)
        try db.saveSnippet(second)
        try db.saveSnippet(third)

        try db.moveSnippet(id: third.id, toFolder: folder.id, atIndex: 0)
        var snippets = try db.fetchSnippets(inFolder: folder.id)
        XCTAssertEqual(snippets.map(\.title), ["Third", "First", "Second"])
        XCTAssertEqual(snippets.map(\.sortIndex), [0, 1, 2])

        try db.moveSnippet(id: third.id, toFolder: folder.id, atIndex: 3)
        snippets = try db.fetchSnippets(inFolder: folder.id)
        XCTAssertEqual(snippets.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(snippets.map(\.sortIndex), [0, 1, 2])
    }

    func testMoveSnippetBetweenFoldersNormalizesBothFolders() throws {
        let db = try makeService()
        let source = SnippetFolder(title: "Source", sortIndex: 0)
        let destination = SnippetFolder(title: "Destination", sortIndex: 1)
        try db.saveFolder(source)
        try db.saveFolder(destination)

        let sourceFirst = Snippet(folderId: source.id, title: "Source First", sortIndex: 4)
        let moving = Snippet(folderId: source.id, title: "Moving", sortIndex: 9)
        let destinationFirst = Snippet(folderId: destination.id, title: "Destination First", sortIndex: 3)
        let destinationLast = Snippet(folderId: destination.id, title: "Destination Last", sortIndex: 8)
        try db.saveSnippet(sourceFirst)
        try db.saveSnippet(moving)
        try db.saveSnippet(destinationFirst)
        try db.saveSnippet(destinationLast)

        try db.moveSnippet(id: moving.id, toFolder: destination.id, atIndex: 1)

        let sourceSnippets = try db.fetchSnippets(inFolder: source.id)
        XCTAssertEqual(sourceSnippets.map(\.title), ["Source First"])
        XCTAssertEqual(sourceSnippets.map(\.sortIndex), [0])

        let destinationSnippets = try db.fetchSnippets(inFolder: destination.id)
        XCTAssertEqual(
            destinationSnippets.map(\.title),
            ["Destination First", "Moving", "Destination Last"]
        )
        XCTAssertEqual(destinationSnippets.map(\.sortIndex), [0, 1, 2])
        XCTAssertEqual(destinationSnippets[1].folderId, destination.id)
    }

    func testMoveSnippetBetweenRootAndFolder() throws {
        let db = try makeService()
        let folder = SnippetFolder(title: "Folder", sortIndex: 0)
        try db.saveFolder(folder)

        let rootFirst = Snippet(title: "Root First", sortIndex: 0)
        let rootLast = Snippet(title: "Root Last", sortIndex: 1)
        let folderSnippet = Snippet(folderId: folder.id, title: "Folder Snippet", sortIndex: 0)
        try db.saveSnippet(rootFirst)
        try db.saveSnippet(rootLast)
        try db.saveSnippet(folderSnippet)

        try db.moveSnippet(id: rootFirst.id, toFolder: folder.id, atIndex: 0)
        XCTAssertEqual(
            try db.fetchSnippets(inFolder: folder.id).map(\.title),
            ["Root First", "Folder Snippet"]
        )
        XCTAssertEqual(try db.fetchRootSnippets().map(\.title), ["Root Last"])

        try db.moveSnippet(id: folderSnippet.id, toFolder: nil, atIndex: 0)
        let rootSnippets = try db.fetchRootSnippets()
        XCTAssertEqual(rootSnippets.map(\.title), ["Folder Snippet", "Root Last"])
        XCTAssertEqual(rootSnippets.map(\.sortIndex), [0, 1])
    }

    func testMoveSnippetRejectsMissingRecordsWithoutChangingOrder() throws {
        let db = try makeService()
        let folder = SnippetFolder(title: "Folder", sortIndex: 0)
        try db.saveFolder(folder)
        let snippet = Snippet(folderId: folder.id, title: "Unmoved", sortIndex: 0)
        try db.saveSnippet(snippet)

        XCTAssertThrowsError(
            try db.moveSnippet(id: "missing", toFolder: folder.id, atIndex: 0)
        )
        XCTAssertThrowsError(
            try db.moveSnippet(id: snippet.id, toFolder: "missing", atIndex: 0)
        )

        let snippets = try db.fetchSnippets(inFolder: folder.id)
        XCTAssertEqual(snippets.map(\.id), [snippet.id])
        XCTAssertEqual(snippets.map(\.sortIndex), [0])
    }

    func testFieldUpdatesDoNotUndoSnippetMove() throws {
        let db = try makeService()
        let source = SnippetFolder(title: "Source", sortIndex: 0)
        let destination = SnippetFolder(title: "Destination", sortIndex: 1)
        try db.saveFolder(source)
        try db.saveFolder(destination)
        let snippet = Snippet(folderId: source.id, title: "Before", content: "Old", sortIndex: 0)
        try db.saveSnippet(snippet)

        try db.moveSnippet(id: snippet.id, toFolder: destination.id, atIndex: 0)
        try db.updateSnippetTitle(id: snippet.id, title: "After")
        try db.updateSnippetContent(id: snippet.id, content: "New")

        XCTAssertTrue(try db.fetchSnippets(inFolder: source.id).isEmpty)
        let movedSnippet = try XCTUnwrap(db.fetchSnippets(inFolder: destination.id).first)
        XCTAssertEqual(movedSnippet.folderId, destination.id)
        XCTAssertEqual(movedSnippet.sortIndex, 0)
        XCTAssertEqual(movedSnippet.title, "After")
        XCTAssertEqual(movedSnippet.content, "New")
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

    func testExportPreservesReorderedSnippetOrder() throws {
        let dbQueue = try makeDbQueue()
        let db = try DatabaseService(dbQueue: dbQueue)
        let folder = SnippetFolder(title: "Ordered", sortIndex: 0)
        try db.saveFolder(folder)

        let first = Snippet(folderId: folder.id, title: "First", sortIndex: 0)
        let second = Snippet(folderId: folder.id, title: "Second", sortIndex: 1)
        let third = Snippet(folderId: folder.id, title: "Third", sortIndex: 2)
        try db.saveSnippet(first)
        try db.saveSnippet(second)
        try db.saveSnippet(third)
        try db.moveSnippet(id: third.id, toFolder: folder.id, atIndex: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-export-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: url) }
        try SnippetImportExport.exportXML(from: dbQueue, to: url)

        let xmlDocument = try XMLDocument(contentsOf: url)
        let snippetElements = try XCTUnwrap(
            xmlDocument.rootElement()?
                .elements(forName: "folder").first?
                .elements(forName: "snippets").first?
                .elements(forName: "snippet")
        )
        let titles = snippetElements.compactMap {
            $0.elements(forName: "title").first?.stringValue
        }
        XCTAssertEqual(titles, ["Third", "First", "Second"])
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
