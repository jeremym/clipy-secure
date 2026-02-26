import Defaults
import SwiftUI

struct TypeSettingsView: View {
    @Default(.storeTypes) var storeTypes

    var body: some View {
        Form {
            Section("Pasteboard types to store") {
                typeToggle(type: .string, label: "Plain Text")
                typeToggle(type: .rtf, label: "Rich Text (RTF)")
                typeToggle(type: .rtfd, label: "Rich Text with Attachments (RTFD)")
                typeToggle(type: .pdf, label: "PDF")
                typeToggle(type: .filenames, label: "File Paths")
                typeToggle(type: .url, label: "URLs")
                typeToggle(type: .tiff, label: "Images (TIFF/PNG)")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func typeToggle(type: ClipContentType, label: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { storeTypes.contains(type.rawValue) },
            set: { enabled in
                if enabled {
                    storeTypes.insert(type.rawValue)
                } else {
                    storeTypes.remove(type.rawValue)
                }
            }
        ))
    }
}
