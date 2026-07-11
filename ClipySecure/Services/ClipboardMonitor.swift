import AppKit
import Defaults
import Foundation
import OSLog

actor ClipboardMonitor {
    private let databaseService: DatabaseService
    private let excludeAppService: ExcludeAppService?
    private let dataCleanupService: DataCleanupService?
    private var lastChangeCount: Int = 0
    private var lastSetChangeCount: Int = 0
    private var monitoringTask: Task<Void, Never>?
    /// Tracks unpinned inserts since last cleanup to batch limit enforcement
    private var insertsSinceCleanup: Int = 0
    private static let cleanupBuffer = 10

    init(
        databaseService: DatabaseService,
        excludeAppService: ExcludeAppService? = nil,
        dataCleanupService: DataCleanupService? = nil
    ) {
        self.databaseService = databaseService
        self.excludeAppService = excludeAppService
        self.dataCleanupService = dataCleanupService
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task {
            lastChangeCount = await MainActor.run { NSPasteboard.general.changeCount }

            while !Task.isCancelled {
                let intervalSeconds = Defaults[.pollingInterval]
                let intervalMs = Int(intervalSeconds * 1000)
                try? await Task.sleep(for: .milliseconds(intervalMs))
                await pollClipboard()
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func pollClipboard() async {
        let currentCount = await MainActor.run {
            NSPasteboard.general.changeCount
        }

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard currentCount != lastSetChangeCount else { return }

        // Check if the copy could have come from an excluded app. The copy
        // happened at most one polling interval ago, so pass that window.
        if let excludeService = excludeAppService {
            let pollWindow = Defaults[.pollingInterval] + 0.1
            let excluded = await MainActor.run {
                excludeService.isCurrentAppExcluded(pollWindow: pollWindow)
            }
            if excluded { return }
        }

        // Use PasteboardReader for full multi-type reading + concealed type detection
        let respectConcealed = Defaults[.respectConcealedType]
        let allowedTypes = Defaults[.storeTypes]

        guard let content = await MainActor.run(body: {
            PasteboardReader.read(respectConcealedType: respectConcealed)
        }) else { return }

        // Filter: check if at least one detected type is in the allowed set
        let hasAllowedType = content.types.contains { allowedTypes.contains($0.rawValue) }
        guard hasAllowedType else { return }

        let clip = ClipItem(content: content)
        do {
            try databaseService.save(clip: clip, overwriteDuplicates: Defaults[.overwriteSameHistory])
        } catch {
            Logger.database.error("Failed to save clip: \(error.localizedDescription)")
        }

        // Batch limit enforcement: only run cleanup after a buffer of inserts
        insertsSinceCleanup += 1
        if insertsSinceCleanup >= Self.cleanupBuffer, let cleanup = dataCleanupService {
            do {
                try cleanup.enforceLimit(Defaults[.maxHistorySize])
            } catch {
                Logger.database.error("Failed to enforce history limit: \(error.localizedDescription)")
            }
            insertsSinceCleanup = 0
        }
    }

    func updateLastSetChangeCount(_ count: Int) {
        lastSetChangeCount = count
    }
}
