import AppKit
import Defaults
import Foundation

actor ClipboardMonitor {
    private let databaseService: DatabaseService
    private let excludeAppService: ExcludeAppService?
    private var lastChangeCount: Int = 0
    private var lastSetChangeCount: Int = 0
    private var monitoringTask: Task<Void, Never>?

    init(databaseService: DatabaseService, excludeAppService: ExcludeAppService? = nil) {
        self.databaseService = databaseService
        self.excludeAppService = excludeAppService
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

        // Check if current frontmost app is excluded
        if let excludeService = excludeAppService {
            let excluded = await MainActor.run {
                excludeService.isCurrentAppExcluded()
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
        try? databaseService.save(clip: clip)
    }

    func updateLastSetChangeCount(_ count: Int) {
        lastSetChangeCount = count
    }
}
