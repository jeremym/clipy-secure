import Defaults
import Foundation
import GRDB

final class DataCleanupService: Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Returns the number of rows deleted.
    @discardableResult
    func deleteExpired(olderThan interval: TimeInterval) throws -> Int {
        let cutoff = Date().addingTimeInterval(-interval)
        return try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM clipItem
                    WHERE isPinned = 0 AND isMemory = 0 AND updatedAt < ?
                    """,
                arguments: [cutoff]
            )
            return db.changesCount
        }
    }

    /// Returns the number of rows deleted.
    @discardableResult
    func enforceLimit(_ limit: Int) throws -> Int {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM clipItem WHERE id NOT IN (
                        SELECT id FROM clipItem WHERE isPinned = 1
                        UNION ALL
                        SELECT id FROM clipItem WHERE isMemory = 1
                        UNION ALL
                        SELECT id FROM (
                            SELECT id FROM clipItem WHERE isPinned = 0 AND isMemory = 0
                            ORDER BY updatedAt DESC LIMIT ?
                        )
                    )
                    """,
                arguments: [limit]
            )
            return db.changesCount
        }
    }

    func runCleanup() throws {
        let historyLimit = Defaults[.maxHistorySize]
        let expirationInterval = Defaults[.historyExpirationSeconds]

        var deletedCount = 0

        if expirationInterval > 0 {
            deletedCount += try deleteExpired(olderThan: expirationInterval)
        }
        deletedCount += try enforceLimit(historyLimit)

        // Freed pages still hold deleted content until VACUUM overwrites them.
        // A non-empty freelist means deletions happened since the last vacuum
        // (e.g. ClipboardMonitor's limit enforcement between cleanups).
        if deletedCount == 0 {
            deletedCount = try dbQueue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
            }
        }

        // VACUUM reclaims disk space and overwrites deleted data so it cannot
        // be recovered with forensic tools. Only worth the file rewrite when
        // something was actually deleted.
        if deletedCount > 0 {
            try dbQueue.vacuum()
        }
    }
}
