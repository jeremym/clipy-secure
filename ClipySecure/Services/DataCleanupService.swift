import Defaults
import Foundation
import GRDB

final class DataCleanupService: Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func deleteExpired(olderThan interval: TimeInterval) throws {
        let cutoff = Date().addingTimeInterval(-interval)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM clipItem
                    WHERE isPinned = 0 AND isMemory = 0 AND updatedAt < ?
                    """,
                arguments: [cutoff]
            )
        }
    }

    func enforceLimit(_ limit: Int) throws {
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
        }
    }

    func runCleanup() throws {
        let historyLimit = Defaults[.maxHistorySize]
        let expirationInterval = Defaults[.historyExpirationSeconds]

        if expirationInterval > 0 {
            try deleteExpired(olderThan: expirationInterval)
        }
        try enforceLimit(historyLimit)
    }
}
