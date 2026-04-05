import Defaults
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.maxHistorySize) var maxHistorySize
    @Default(.numberOfItemsInline) var numberOfItemsInline
    @Default(.numberOfItemsInFolder) var numberOfItemsInFolder
    @Default(.pollingInterval) var pollingInterval

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
