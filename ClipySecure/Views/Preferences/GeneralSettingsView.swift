import Defaults
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.maxHistorySize) var maxHistorySize
    @Default(.pollingInterval) var pollingInterval

    var body: some View {
        Form {
            Section("History") {
                Stepper(
                    "Max history size: \(maxHistorySize)",
                    value: $maxHistorySize,
                    in: 10...999
                )
            }

            Section("Monitoring") {
                VStack(alignment: .leading) {
                    Text("Polling interval: \(String(format: "%.2fs", pollingInterval))")
                    Slider(value: $pollingInterval, in: 0.25...2.0, step: 0.25)
                }
            }

            Section("Startup") {
                Text("Launch at Login")
                    .foregroundStyle(.secondary)
                Text("(Available in Phase 6)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
