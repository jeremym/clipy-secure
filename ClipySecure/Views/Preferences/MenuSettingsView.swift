import Defaults
import SwiftUI

struct MenuSettingsView: View {
    @Default(.menuItemTitleMaxLength) var menuItemTitleMaxLength
    @Default(.showImagesInMenu) var showImagesInMenu
    @Default(.showClearHistoryItem) var showClearHistoryItem
    @Default(.reorderAfterPaste) var reorderAfterPaste
    @Default(.showTooltips) var showTooltips
    @Default(.tooltipMaxLength) var tooltipMaxLength
    @Default(.memorySnippetFolderName) var memorySnippetFolderName

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Title max length: \(menuItemTitleMaxLength)",
                    value: $menuItemTitleMaxLength,
                    in: 20...200
                )
                Toggle("Show image thumbnails", isOn: $showImagesInMenu)
            } header: {
                Text("Display")
            } footer: {
                Text("Controls how each clipboard entry appears in the menu. Longer titles show more context; image thumbnails show a preview for copied images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Move pasted item to top", isOn: $reorderAfterPaste)
                Toggle("Show \u{201C}Clear All\u{201D} in menu", isOn: $showClearHistoryItem)
            } header: {
                Text("Behavior")
            } footer: {
                Text("When \u{201C}Move pasted item to top\u{201D} is on, selecting an item bumps it to the first position so frequently used clips stay accessible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show tooltips on hover", isOn: $showTooltips)
                if showTooltips {
                    Stepper(
                        "Tooltip max length: \(tooltipMaxLength)",
                        value: $tooltipMaxLength,
                        in: 50...500
                    )
                }
            } header: {
                Text("Tooltips")
            } footer: {
                Text("Tooltips show a longer preview of each clipboard entry when you hover over it in the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Snippet folder name", text: $memorySnippetFolderName)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Memory")
            } footer: {
                Text("When you promote a memory item to a snippet, it\u{2019}s saved in a folder with this name. The folder is created automatically if it doesn\u{2019}t exist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
