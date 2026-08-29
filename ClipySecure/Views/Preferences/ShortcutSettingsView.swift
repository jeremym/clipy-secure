import KeyboardShortcuts
import SwiftUI

struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            Section("Global Keyboard Shortcuts") {
                shortcutRow("Main Menu", name: .toggleMainMenu)
                shortcutRow("Clipboard History Search", name: .toggleHistoryMenu)
                shortcutRow("Clear History", name: .clearHistory)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func shortcutRow(_ label: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
        }
    }
}
