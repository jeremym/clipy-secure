import AppKit

/// Makes the shortcut labels in the clip menu ("a", "b", "1"…) fire on a single
/// keystroke instead of AppKit's type-select, which highlights the row and waits
/// for Return.
///
/// The keys have to be real `keyEquivalent`s — the delegate hook that would
/// avoid drawing them, `menuHasKeyEquivalent(_:for:target:action:)`, is not
/// consulted while a menu is tracking. Real key equivalents bring one problem:
/// `performKeyEquivalent` searches *closed* submenus too, so "3" typed inside
/// folder 2 would fire folder 1's third clip. Hence the assignment is dynamic —
/// items carry their key in `identifier`, and only the menu the user is looking
/// at has live key equivalents. Ancestors are suspended while a submenu is open
/// and restored when it closes.
@MainActor
final class MenuKeyRouter: NSObject, NSMenuDelegate {
    static let shared = MenuKeyRouter()

    private static let identifierPrefix = "clipkey:"

    /// Menus open right now, outermost first. Only the last one holds live keys.
    private var openMenus: [NSMenu] = []

    /// Records that `item` should fire on `key`, a single character.
    ///
    /// The key rides on `identifier` rather than a side table so it lives and
    /// dies with the item — these menus are rebuilt from scratch on every open.
    static func assign(key: String, to item: NSMenuItem) {
        guard key.count == 1 else { return }
        item.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + key.lowercased())
    }

    private static func key(for item: NSMenuItem) -> String? {
        guard let raw = item.identifier?.rawValue, raw.hasPrefix(identifierPrefix) else { return nil }
        return String(raw.dropFirst(identifierPrefix.count))
    }

    /// Makes `submenu` participate in single-key firing. The root menu keeps its
    /// own delegate and forwards `noteOpened`/`noteClosed` instead.
    static func attach(to submenu: NSMenu) {
        submenu.delegate = shared
    }

    // MARK: - Open-menu tracking

    func noteOpened(_ menu: NSMenu) {
        openMenus.append(menu)
        for ancestor in openMenus.dropLast() {
            setKeysActive(false, in: ancestor)
        }
        setKeysActive(true, in: menu)
    }

    func noteClosed(_ menu: NSMenu) {
        setKeysActive(false, in: menu)
        openMenus.removeAll { $0 === menu }
        if let uncovered = openMenus.last {
            setKeysActive(true, in: uncovered)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        noteOpened(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        noteClosed(menu)
    }

    // MARK: - Key equivalents

    private func setKeysActive(_ active: Bool, in menu: NSMenu) {
        for (index, item) in menu.items.enumerated() {
            // An alternate only stays paired with the item above it while both
            // carry the same key equivalent and differ by modifier, so it has to
            // track its base item rather than carry a key of its own.
            let base = item.isAlternate ? (index > 0 ? menu.items[index - 1] : nil) : item
            guard let base, let key = Self.key(for: base) else { continue }

            item.keyEquivalent = active ? key : ""
            item.keyEquivalentModifierMask = item.isAlternate ? .option : []
        }
    }
}
