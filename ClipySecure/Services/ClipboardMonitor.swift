import AppKit
import Foundation

actor ClipboardMonitor {
    private let databaseService: DatabaseService
    private var lastChangeCount: Int = 0
    private var lastSetChangeCount: Int = 0
    private var monitoringTask: Task<Void, Never>?

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task {
            lastChangeCount = await MainActor.run { NSPasteboard.general.changeCount }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Constants.pollingIntervalMs))
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

        // Use PasteboardReader for full multi-type reading + concealed type detection
        guard let content = await MainActor.run(body: {
            PasteboardReader.read()
        }) else { return }

        let clip = ClipItem(content: content)
        try? databaseService.save(clip: clip)
    }

    func updateLastSetChangeCount(_ count: Int) {
        lastSetChangeCount = count
    }
}
