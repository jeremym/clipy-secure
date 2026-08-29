import Cocoa
import KeyboardShortcuts
import OSLog

extension KeyboardShortcuts.Name {
    static let toggleMainMenu = Self("toggleMainMenu", default: .init(.v, modifiers: [.command, .shift]))
    static let toggleHistoryMenu = Self("toggleHistoryMenu", default: .init(.v, modifiers: [.command, .control]))
    static let clearHistory = Self("clearHistory")
}

@MainActor
final class HotKeyService {
    private let statusBarController: StatusBarController
    private let databaseService: DatabaseService
    private let historyPanelController: HistoryPanelController?

    init(
        statusBarController: StatusBarController,
        databaseService: DatabaseService,
        historyPanelController: HistoryPanelController? = nil
    ) {
        self.statusBarController = statusBarController
        self.databaseService = databaseService
        self.historyPanelController = historyPanelController
        registerShortcuts()
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleMainMenu) { [weak self] in
            self?.statusBarController.popUpMainMenu()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleHistoryMenu) { [weak self] in
            // Use history panel (with search) instead of menu popup
            if let panel = self?.historyPanelController {
                panel.togglePanel()
            } else {
                self?.statusBarController.popUpHistoryMenu()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .clearHistory) { [weak self] in
            let alert = NSAlert()
            alert.messageText = String(localized: "Clear History")
            alert.informativeText = String(localized: "Are you sure you want to clear all clipboard history? This cannot be undone. Memorized items will be preserved.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Clear"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            // Destructive action must not be the Return-key default — the
            // alert can appear while the user is typing in another app.
            alert.buttons[0].hasDestructiveAction = true
            alert.buttons[0].keyEquivalent = ""
            alert.buttons[1].keyEquivalent = "\r"
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                try self?.databaseService.deleteAll()
            } catch {
                Logger.database.error("Failed to clear history: \(error.localizedDescription)")
            }
        }
    }
}
