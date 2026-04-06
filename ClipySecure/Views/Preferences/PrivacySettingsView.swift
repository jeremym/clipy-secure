import Defaults
import OSLog
import SwiftUI

struct PrivacySettingsView: View {
    let databaseService: DatabaseService
    @Default(.historyExpirationSeconds) var historyExpirationSeconds
    @Default(.respectConcealedType) var respectConcealedType
    @Default(.overwriteSameHistory) var overwriteSameHistory
    @State private var showClearConfirmation = false

    private var expirationBinding: Binding<ExpirationOption> {
        Binding(
            get: { ExpirationOption.from(seconds: historyExpirationSeconds) },
            set: { historyExpirationSeconds = $0.seconds }
        )
    }

    var body: some View {
        Form {
            Section("History Expiration") {
                Picker("Auto-delete history after:", selection: expirationBinding) {
                    ForEach(ExpirationOption.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section("Privacy") {
                Toggle("Respect concealed type (skip password manager entries)", isOn: $respectConcealedType)
                Toggle("Overwrite duplicate history entries", isOn: $overwriteSameHistory)
            }

            Section("Danger Zone") {
                Button("Clear All History", role: .destructive) {
                    showClearConfirmation = true
                }
                .confirmationDialog(
                    "Are you sure you want to clear all clipboard history?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All History", role: .destructive) {
                        do {
                            try databaseService.deleteAll()
                        } catch {
                            Logger.database.error("Failed to clear history: \(error.localizedDescription)")
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private enum ExpirationOption: CaseIterable {
    case never
    case oneDay
    case sevenDays
    case thirtyDays

    var label: String {
        switch self {
        case .never: String(localized: "Never")
        case .oneDay: String(localized: "24 hours")
        case .sevenDays: String(localized: "7 days")
        case .thirtyDays: String(localized: "30 days")
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .never: 0
        case .oneDay: 86400
        case .sevenDays: 604_800
        case .thirtyDays: 2_592_000
        }
    }

    static func from(seconds: TimeInterval) -> ExpirationOption {
        switch seconds {
        case 0: .never
        case 86400: .oneDay
        case 604_800: .sevenDays
        case 2_592_000: .thirtyDays
        default: .thirtyDays
        }
    }
}
