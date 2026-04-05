import Defaults
import LaunchAtLogin
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
                LaunchAtLogin.Toggle(String(localized: "Launch at Login"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
