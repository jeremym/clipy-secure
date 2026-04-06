import Defaults
import Foundation

extension Defaults.Keys {
    static let maxHistorySize = Key<Int>("maxHistorySize", default: 32)
    static let menuItemTitleMaxLength = Key<Int>("menuItemTitleMaxLength", default: 40)
    static let numberOfItemsInline = Key<Int>("numberOfItemsInline", default: 2)
    static let numberOfItemsInFolder = Key<Int>("numberOfItemsInFolder", default: 10)
    static let showNumbersInMenu = Key<Bool>("showNumbersInMenu", default: true)
    static let reorderAfterPaste = Key<Bool>("reorderAfterPaste", default: true)
    static let showClearHistoryItem = Key<Bool>("showClearHistoryItem", default: true)
    static let showTooltips = Key<Bool>("showTooltips", default: true)
    static let tooltipMaxLength = Key<Int>("tooltipMaxLength", default: 200)
    static let showImagesInMenu = Key<Bool>("showImagesInMenu", default: true)
    static let overwriteSameHistory = Key<Bool>("overwriteSameHistory", default: true)
    static let respectConcealedType = Key<Bool>("respectConcealedType", default: true)
    static let historyExpirationSeconds = Key<TimeInterval>("historyExpirationSeconds", default: 2_592_000)
    static let storeTypes = Key<Set<String>>("storeTypes", default: Set(ClipContentType.allCases.map(\.rawValue)))
    static let pollingInterval = Key<Double>("pollingInterval", default: 0.5)
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)
    static let memorySnippetFolderName = Key<String>("memorySnippetFolderName", default: "Saved Memories")
    static let maxMemorySize = Key<Int>("maxMemorySize", default: 42)
    static let numberOfMemoryItemsInline = Key<Int>("numberOfMemoryItemsInline", default: 2)
    static let numberOfItemsPerMemoryFolder = Key<Int>("numberOfItemsPerMemoryFolder", default: 40)
}

extension ClipContentType: CaseIterable {
    static var allCases: [ClipContentType] {
        [.string, .rtf, .rtfd, .pdf, .filenames, .url, .tiff]
    }
}
