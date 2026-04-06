import Defaults
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.maxHistorySize) var maxHistorySize
    @Default(.numberOfItemsInline) var numberOfItemsInline
    @Default(.numberOfItemsInFolder) var numberOfItemsInFolder
    @Default(.pollingInterval) var pollingInterval
    @Default(.maxMemorySize) var maxMemorySize
    @Default(.numberOfMemoryItemsInline) var numberOfMemoryItemsInline
    @Default(.numberOfItemsPerMemoryFolder) var numberOfItemsPerMemoryFolder

    private var memoryFolderCount: Int {
        guard numberOfItemsPerMemoryFolder > 0 else { return 0 }
        let remaining = maxMemorySize - numberOfMemoryItemsInline
        return remaining > 0 ? Int(ceil(Double(remaining) / Double(numberOfItemsPerMemoryFolder))) : 0
    }

    private var folderCount: Int {
        guard numberOfItemsInFolder > 0 else { return 0 }
        let remaining = maxHistorySize - numberOfItemsInline
        return remaining > 0 ? Int(ceil(Double(remaining) / Double(numberOfItemsInFolder))) : 0
    }

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Max history size: \(maxHistorySize)",
                    value: $maxHistorySize,
                    in: 10...999
                )
                Stepper(
                    "Items shown at top level: \(numberOfItemsInline == 0 ? "All" : "\(numberOfItemsInline)")",
                    value: $numberOfItemsInline,
                    in: 0...50
                )
                Stepper(
                    "Items per folder: \(numberOfItemsInFolder)",
                    value: $numberOfItemsInFolder,
                    in: 5...50
                )
            } header: {
                Text("Clipboard History")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu layout: \(numberOfItemsInline) at top level + \(folderCount) folder\(folderCount == 1 ? "" : "s") of \(numberOfItemsInFolder)")
                    Text("Tip: set max history = inline + (folders \u{00D7} items per folder) for evenly filled folders.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    "Max memory size: \(maxMemorySize)",
                    value: $maxMemorySize,
                    in: 2...999
                )
                Stepper(
                    "Memory items at top level: \(numberOfMemoryItemsInline == 0 ? "All" : "\(numberOfMemoryItemsInline)")",
                    value: $numberOfMemoryItemsInline,
                    in: 0...50
                )
                Stepper(
                    "Items per memory folder: \(numberOfItemsPerMemoryFolder)",
                    value: $numberOfItemsPerMemoryFolder,
                    in: 5...100
                )
            } header: {
                Text("Memory")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu layout: \(numberOfMemoryItemsInline) at top level + \(memoryFolderCount) folder\(memoryFolderCount == 1 ? "" : "s") of \(numberOfItemsPerMemoryFolder)")
                    Text("Tip: set max memory = inline + (folders \u{00D7} items per folder) for evenly filled folders.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Clipboard check interval: \(String(format: "%.2fs", pollingInterval))")
                    Slider(value: $pollingInterval, in: 0.25...2.0, step: 0.25)
                }
            } header: {
                Text("Monitoring")
            } footer: {
                Text("How often ClipySecure checks for new clipboard content. Lower values catch copies faster but use slightly more CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                LaunchAtLogin.Toggle(String(localized: "Launch at Login"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
