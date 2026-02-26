import Defaults
import SwiftUI

struct MenuSettingsView: View {
    @Default(.numberOfItemsInline) var numberOfItemsInline
    @Default(.numberOfItemsInFolder) var numberOfItemsInFolder
    @Default(.showNumbersInMenu) var showNumbersInMenu
    @Default(.menuItemTitleMaxLength) var menuItemTitleMaxLength
    @Default(.showTooltips) var showTooltips
    @Default(.tooltipMaxLength) var tooltipMaxLength
    @Default(.showImagesInMenu) var showImagesInMenu
    @Default(.reorderAfterPaste) var reorderAfterPaste
    @Default(.showClearHistoryItem) var showClearHistoryItem

    var body: some View {
        Form {
            Section("Display") {
                Stepper(
                    "Items inline: \(numberOfItemsInline == 0 ? "All" : "\(numberOfItemsInline)")",
                    value: $numberOfItemsInline,
                    in: 0...50
                )
                Stepper(
                    "Items per folder: \(numberOfItemsInFolder)",
                    value: $numberOfItemsInFolder,
                    in: 5...50
                )
                Stepper(
                    "Title max length: \(menuItemTitleMaxLength)",
                    value: $menuItemTitleMaxLength,
                    in: 20...200
                )
            }

            Section("Options") {
                Toggle("Show numbers in menu", isOn: $showNumbersInMenu)
                Toggle("Show images in menu", isOn: $showImagesInMenu)
                Toggle("Show Clear History item", isOn: $showClearHistoryItem)
                Toggle("Reorder after paste", isOn: $reorderAfterPaste)
            }

            Section("Tooltips") {
                Toggle("Show tooltips", isOn: $showTooltips)
                if showTooltips {
                    Stepper(
                        "Tooltip max length: \(tooltipMaxLength)",
                        value: $tooltipMaxLength,
                        in: 50...500
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
