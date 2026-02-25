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

    init(statusBarController: StatusBarController, databaseService: DatabaseService) {
        self.statusBarController = statusBarController
        self.databaseService = databaseService
        registerShortcuts()
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleMainMenu) { [weak self] in
            self?.statusBarController.popUpMainMenu()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleHistoryMenu) { [weak self] in
            self?.statusBarController.popUpHistoryMenu()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleSnippetMenu) { [weak self] in
            self?.statusBarController.popUpSnippetMenu()
        }

        KeyboardShortcuts.onKeyUp(for: .clearHistory) { [weak self] in
            try? self?.databaseService.deleteAll()
        }
    }
}
