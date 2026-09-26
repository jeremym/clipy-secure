import Defaults
import SwiftUI

struct MenuSettingsView: View {
    @Default(.menuItemTitleMaxLength) var menuItemTitleMaxLength
    @Default(.showImagesInMenu) var showImagesInMenu
    @Default(.showClearHistoryItem) var showClearHistoryItem
    @Default(.reorderAfterPaste) var reorderAfterPaste
    @Default(.showMenuAtMousePointer) var showMenuAtMousePointer
    @Default(.showTooltips) var showTooltips
    @Default(.tooltipMaxLength) var tooltipMaxLength
    @Default(.memorySnippetFolderName) var memorySnippetFolderName
    @Default(.menuShortcutKeys) var menuShortcutKeys

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
                TextField("Shortcut keys", text: $menuShortcutKeys)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: menuShortcutKeys) { _, newValue in
                        // Keep the stored value in the same shape the menu uses:
                        // no spaces, no duplicates, lowercased.
                        let cleaned = String(MenuShortcutKeys.normalized(newValue))
                        if cleaned != newValue {
                            menuShortcutKeys = cleaned
                        }
                    }
                Button("Reset to 1, 2, 3\u{2026}") {
                    menuShortcutKeys = MenuShortcutKeys.default
                }
                .disabled(menuShortcutKeys == MenuShortcutKeys.default)
            } header: {
                Text("Menu shortcut keys")
            } footer: {
                Text("While the clip menu is open, press one of these keys to paste that entry instantly. Inline items take the first keys in order; folders continue after them. Remove a key \u{2014} a digit, say \u{2014} to free it so you can instead type-jump to a snippet folder whose name starts with that character. Only single characters work, so at most the first ten give a shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open menu at mouse pointer", isOn: $showMenuAtMousePointer)
                Toggle("Move pasted item to top", isOn: $reorderAfterPaste)
                Toggle("Show \u{201C}Clear All\u{201D} in menu", isOn: $showClearHistoryItem)
            } header: {
                Text("Behavior")
            } footer: {
                Text("When \u{201C}Open menu at mouse pointer\u{201D} is on, keyboard shortcuts open the clip menu where the cursor is instead of under the menu bar icon. When \u{201C}Move pasted item to top\u{201D} is on, selecting an item bumps it to the first position so frequently used clips stay accessible.")
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
