import AppKit
import Defaults
import OSLog
import SwiftUI

extension ObsidianExportService.Options {
    /// Builds export options from the user's current Defaults. Returns nil when
    /// no vault folder has been chosen yet. Shared by the prefs Test button and
    /// the clip-menu / history-panel "Send to Obsidian" actions.
    static func current() -> ObsidianExportService.Options? {
        let path = Defaults[.obsidianVaultPath]
        guard !path.isEmpty else { return nil }
        return ObsidianExportService.Options(
            vaultURL: URL(fileURLWithPath: path, isDirectory: true),
            subfolder: Defaults[.obsidianSubfolder],
            filenameTemplate: Defaults[.obsidianFilenameTemplate],
            includeFrontmatter: Defaults[.obsidianFrontmatter],
            fenceNonMarkdown: Defaults[.obsidianFenceCode]
        )
    }
}

struct ObsidianSettingsView: View {
    @Default(.obsidianVaultPath) var vaultPath
    @Default(.obsidianSubfolder) var subfolder
    @Default(.obsidianFilenameTemplate) var filenameTemplate
    @Default(.obsidianFrontmatter) var frontmatter
    @Default(.obsidianFenceCode) var fenceCode
    @Default(.obsidianOpenAfterSave) var openAfterSave
    @Default(.obsidianRemoveFromMemory) var removeFromMemory

    private var vaultName: String {
        vaultPath.isEmpty ? "" : (vaultPath as NSString).lastPathComponent
    }

    private var looksLikeVault: Bool {
        guard !vaultPath.isEmpty else { return false }
        return FileManager.default.fileExists(
            atPath: (vaultPath as NSString).appendingPathComponent(".obsidian")
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    if vaultPath.isEmpty {
                        Text("No vault chosen").foregroundStyle(.secondary)
                    } else {
                        Label(vaultName, systemImage: looksLikeVault ? "book.closed" : "exclamationmark.triangle")
                            .foregroundStyle(looksLikeVault ? Color.primary : Color.orange)
                    }
                    Spacer()
                    Button("Choose Vault…", action: chooseVault)
                }
                if !vaultPath.isEmpty, !looksLikeVault {
                    Text("That folder has no .obsidian directory — it may not be a vault. Notes will still be written there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Notes subfolder", text: $subfolder)
                TextField("Filename template", text: $filenameTemplate)
            } header: {
                Text("Vault")
            } footer: {
                Text("`{date}` becomes the date (2026-10-17) and `{title}` the clip's title. Same-day collisions get a “(2)” suffix. Leave the subfolder blank to write into the vault root.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Note Format") {
                Toggle("Add frontmatter (created, source app, tags)", isOn: $frontmatter)
                Toggle("Wrap non-Markdown text in a code fence", isOn: $fenceCode)
            }

            Section {
                Toggle("Open the note in Obsidian after saving", isOn: $openAfterSave)
                Toggle("Remove from Memory after sending", isOn: $removeFromMemory)
            } header: {
                Text("After Sending")
            }

            Section {
                Button("Write a Test Note", action: writeTestNote)
                    .disabled(vaultPath.isEmpty)
            } footer: {
                Text("Obsidian export is one of two ways clip content leaves the encrypted store on purpose (the other is snippet export). Notes are written to your vault as plain, unencrypted Markdown by your explicit action. Nothing is sent over any network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose your Obsidian vault folder")
        if panel.runModal() == .OK, let url = panel.url {
            vaultPath = url.path
        }
    }

    private func writeTestNote() {
        guard let options = ObsidianExportService.Options.current() else { return }
        let sample = ClipItem(
            stringValue: "ClipySecure test note — if you can read this in your vault, Obsidian export works."
        )
        do {
            let url = try ObsidianExportService.export(sample, options: options)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Logger.general.error("Obsidian test note failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't write the test note")
            alert.informativeText = String(localized: "Check that the vault folder exists and is writable.")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
