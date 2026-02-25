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
        let (currentCount, string) = await MainActor.run {
            let pb = NSPasteboard.general
            return (pb.changeCount, pb.string(forType: .string))
        }

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard currentCount != lastSetChangeCount else { return }

        guard let string, !string.isEmpty else { return }

        let clip = ClipItem(stringValue: string)
        try? databaseService.save(clip: clip)
    }

    func updateLastSetChangeCount(_ count: Int) {
        lastSetChangeCount = count
    }
}
