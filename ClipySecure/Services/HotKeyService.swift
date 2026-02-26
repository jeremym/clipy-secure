import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMainMenu = Self("toggleMainMenu", default: .init(.v, modifiers: [.command, .shift]))
    static let toggleHistoryMenu = Self("toggleHistoryMenu", default: .init(.v, modifiers: [.command, .control]))
    static let toggleSnippetMenu = Self("toggleSnippetMenu", default: .init(.b, modifiers: [.command, .shift]))
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

        KeyboardShortcuts.onKeyUp(for: .toggleSnippetMenu) { [weak self] in
            self?.statusBarController.popUpSnippetMenu()
        }

        KeyboardShortcuts.onKeyUp(for: .clearHistory) { [weak self] in
            try? self?.databaseService.deleteAll()
        }
    }
}
