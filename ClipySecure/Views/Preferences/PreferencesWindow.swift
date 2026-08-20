import AppKit
import SwiftUI

private enum PreferencesTab: String, CaseIterable {
    case general
    case menu
    case types
    case shortcuts
    case excludedApps
    case privacy

    var label: String {
        switch self {
        case .general: String(localized: "General")
        case .menu: String(localized: "Menu")
        case .types: String(localized: "Types")
        case .shortcuts: String(localized: "Shortcuts")
        case .excludedApps: String(localized: "Excluded Apps")
        case .privacy: String(localized: "Privacy")
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .menu: "list.bullet"
        case .types: "doc.on.clipboard"
        case .shortcuts: "keyboard"
        case .excludedApps: "xmark.app"
        case .privacy: "lock.shield"
        }
    }

    var itemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("prefs.\(rawValue)")
    }
}

@MainActor
final class PreferencesWindow: NSObject, NSToolbarDelegate {
    private var window: NSWindow?
    private var notificationObserver: Any?
    private let databaseService: DatabaseService
    private var selectedTab: PreferencesTab = .general

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        ActivationPolicyManager.beginWindowSession()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false

        let toolbar = NSToolbar(identifier: "PreferencesToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = selectedTab.itemIdentifier
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        self.window = window
        showTab(selectedTab)

        // Centered only once the first tab's content and the toolbar are in
        // place, so the frame being centered is the final one.
        window.setContentSize(NSSize(width: 620, height: 580))
        window.center()

        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowClose()
            }
        }

        window.presentDeferred()
    }

    func close() {
        window?.close()
    }

    private func handleWindowClose() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        window = nil
        ActivationPolicyManager.endWindowSession()
    }

    // MARK: - Tab Switching

    private func showTab(_ tab: PreferencesTab) {
        selectedTab = tab
        window?.title = tab.label

        // Preserve window position when switching tabs. Skipped on the initial
        // show, where no content is installed yet and the frame is not yet
        // meaningful — showWindow() centers once the real content is in place.
        let savedFrame = window?.contentViewController == nil ? nil : window?.frame

        let view: AnyView
        switch tab {
        case .general:
            view = AnyView(GeneralSettingsView())
        case .menu:
            view = AnyView(MenuSettingsView())
        case .types:
            view = AnyView(TypeSettingsView())
        case .shortcuts:
            view = AnyView(ShortcutSettingsView())
        case .excludedApps:
            view = AnyView(ExcludedAppsView(databaseService: databaseService))
        case .privacy:
            view = AnyView(PrivacySettingsView(databaseService: databaseService))
        }

        let controller = NSHostingController(rootView:
            view.frame(minWidth: 550, minHeight: 480)
        )
        window?.contentViewController = controller

        // Restore window position after content swap
        if let frame = savedFrame {
            window?.setFrame(frame, display: true)
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = PreferencesTab.allCases.first(where: { $0.itemIdentifier == itemIdentifier }) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.label
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.label)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesTab.allCases.map(\.itemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesTab.allCases.map(\.itemIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesTab.allCases.map(\.itemIdentifier)
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = PreferencesTab.allCases.first(where: { $0.itemIdentifier == sender.itemIdentifier }) else {
            return
        }
        showTab(tab)
    }
}
