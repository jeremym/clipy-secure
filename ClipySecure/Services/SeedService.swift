import Defaults
import Foundation
import OSLog

/// Seeds a small set of example snippets on the very first launch, then never
/// again. Deliberately not a GRDB migration: migrations run against the
/// in-memory test database and several tests assert on empty snippet tables.
///
/// Privacy note: snippet content is stored **plaintext** by design (the snippet
/// tables are unencrypted, unlike clip content). The example content below is
/// therefore deliberately non-sensitive — it only explains how the app works.
enum SeedService {
    static let exampleFolderTitle = "Examples"

    /// The example snippets, in display order. Non-sensitive by design.
    static let exampleSnippets: [(title: String, content: String)] = [
        (
            "Welcome to Snippets",
            """
            Snippets are reusable text you keep forever. Press ⌘⇧V, open a \
            folder, then tap its key to paste. Edit these in Preferences — or \
            just delete this Examples folder when you're done.
            """
        ),
        (
            "Save to Memory",
            """
            In the clip menu, hold ⌥ on any row to reveal its actions: the \
            brain (m) keeps a clip from expiring, the clipboard promotes a \
            saved clip into a snippet like this one.
            """
        ),
        (
            "Send to Obsidian",
            """
            Hold ⌥ on a clip and pick the book (o) to drop it into your \
            Obsidian vault as a note. Choose your vault first in \
            Preferences ▸ Obsidian.
            """
        ),
    ]

    /// Whether a first-run seed should actually insert examples. Pure decision
    /// logic (no Defaults / no DB) so it is deterministically unit-testable:
    /// seed only when we have never seeded *and* the store is empty, so an
    /// upgrading user who already has snippets is never surprised.
    static func shouldSeed(alreadySeeded: Bool, storeEmpty: Bool) -> Bool {
        !alreadySeeded && storeEmpty
    }

    /// App entry point: seed exactly once. Guarded by a Defaults marker *and* an
    /// empty-store check, so an upgrading user who already has snippets (but
    /// somehow lacks the marker) is never surprised by injected examples.
    @discardableResult
    static func seedExampleSnippetsIfNeeded(into db: DatabaseService) -> Bool {
        guard !Defaults[.hasSeededExampleSnippets] else { return false }
        do {
            let storeEmpty = try db.isSnippetStoreEmpty()
            guard shouldSeed(alreadySeeded: false, storeEmpty: storeEmpty) else {
                // Existing snippets present: record that we've "seeded" so we
                // never check again, but leave the user's store untouched.
                Defaults[.hasSeededExampleSnippets] = true
                return false
            }
            try seedExamples(into: db)
            Defaults[.hasSeededExampleSnippets] = true
            return true
        } catch {
            Logger.general.error("Failed to seed example snippets: \(error.localizedDescription)")
            return false
        }
    }

    /// Inserts the example folder and its snippets. Pure DB work — unit-testable
    /// with an in-memory DatabaseService. Does not touch the Defaults marker.
    static func seedExamples(into db: DatabaseService) throws {
        let folder = SnippetFolder(title: exampleFolderTitle, sortIndex: 0)
        try db.saveFolder(folder)
        for (index, example) in exampleSnippets.enumerated() {
            try db.saveSnippet(
                Snippet(folderId: folder.id, title: example.title, content: example.content, sortIndex: index)
            )
        }
    }
}
