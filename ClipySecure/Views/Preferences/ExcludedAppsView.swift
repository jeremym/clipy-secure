import SwiftUI

struct ExcludedAppsView: View {
    let databaseService: DatabaseService
    @State private var excludedApps: [ExcludedApp] = []
    @State private var selectedAppId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps excluded from clipboard monitoring:")
                .font(.headline)

            List(excludedApps, selection: $selectedAppId) { app in
                HStack {
                    if let icon = iconForBundleId(app.bundleId) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    VStack(alignment: .leading) {
                        Text(app.appName)
                        Text(app.bundleId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(app.id)
            }
            .frame(minHeight: 200)

            HStack {
                Button(action: addApp) {
                    Image(systemName: "plus")
                }
                Button(action: removeSelectedApp) {
                    Image(systemName: "minus")
                }
                .disabled(selectedAppId == nil)
            }
        }
        .padding()
        .onAppear { loadApps() }
    }

    private func loadApps() {
        excludedApps = (try? databaseService.fetchExcludedApps()) ?? []
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }

        let appName = url.deletingPathExtension().lastPathComponent

        do {
            try databaseService.addExcludedApp(bundleId: bundleId, appName: appName)
            loadApps()
        } catch {
            // Ignore duplicate errors
        }
    }

    private func removeSelectedApp() {
        guard let id = selectedAppId else { return }
        try? databaseService.removeExcludedApp(id: id)
        selectedAppId = nil
        loadApps()
    }

    private func iconForBundleId(_ bundleId: String) -> NSImage? {
        guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: path.path)
    }
}
