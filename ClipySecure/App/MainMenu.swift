import AppKit

/// The app has no nib, so `NSApplication` starts with `mainMenu == nil` and
/// nothing ever assigns one.
///
/// That costs more than the visible menu bar. AppKit dispatches the standard
/// editing shortcuts through main-menu key equivalents, so with no Edit menu
/// Cmd-C/X/V/Z and Select All silently do nothing inside the snippet editor and
/// the search field — and with no App menu there is no Cmd-Q, leaving a window
/// the user cannot quit from the keyboard.
///
/// Accessory apps don't display this menu bar, but the key equivalents still
/// resolve whenever one of the app's own windows is key, which is exactly when
/// they're needed.
@MainActor
enum MainMenu {
    static func install() {
        let appName = ProcessInfo.processInfo.processName

        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu(appName: appName))
        mainMenu.addItem(editMenu())
        mainMenu.addItem(windowMenu())
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menus

    private static func appMenu(appName: String) -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(
            title: String(localized: "About \(appName)"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Hide \(appName)"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        menu.addItem(
            title: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Quit \(appName)"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return wrap(menu, title: appName)
    }

    private static func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Edit"))
        // String selectors: these are responder-chain actions, not methods on a
        // single concrete class, so #selector would need an arbitrary owner.
        menu.addItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(
            title: String(localized: "Redo"),
            action: Selector(("redo:")),
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        )
        menu.addItem(.separator())
        menu.addItem(title: String(localized: "Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        menu.addItem(title: String(localized: "Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        menu.addItem(title: String(localized: "Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        menu.addItem(
            title: String(localized: "Select All"),
            action: Selector(("selectAll:")),
            keyEquivalent: "a"
        )
        return wrap(menu, title: String(localized: "Edit"))
    }

    private static func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(
            title: String(localized: "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(
            title: String(localized: "Close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        let item = wrap(menu, title: String(localized: "Window"))
        NSApp.windowsMenu = menu
        return item
    }

    private static func wrap(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

private extension NSMenu {
    func addItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        addItem(item)
    }
}
