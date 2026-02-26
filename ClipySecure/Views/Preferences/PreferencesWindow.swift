import AppKit
import SwiftUI

@MainActor
final class PreferencesWindow {
    private var window: NSWindow?
    private var hostingController: NSHostingController<PreferencesTabView>?
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let tabView = PreferencesTabView(databaseService: databaseService)
        let controller = NSHostingController(rootView: tabView)
        hostingController = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = controller
        self.window = window

        Task {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func close() {
        window?.close()
        window = nil
        hostingController = nil
    }
}

struct PreferencesTabView: View {
    let databaseService: DatabaseService

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            MenuSettingsView()
                .tabItem { Label("Menu", systemImage: "list.bullet") }
            TypeSettingsView()
                .tabItem { Label("Types", systemImage: "doc.on.clipboard") }
            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            ExcludedAppsView(databaseService: databaseService)
                .tabItem { Label("Excluded Apps", systemImage: "xmark.app") }
            PrivacySettingsView(databaseService: databaseService)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 420)
    }
}
