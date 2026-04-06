import Cocoa

@MainActor
final class PasteService {
    private let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    /// Writes a ClipItem's content to the pasteboard. Returns the new change count,
    /// or nil if there was nothing to write.
    func writeToClipboard(_ item: ClipItem) -> Int? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wroteContent = false

        if let rtfData = item.rtfData {
            pasteboard.setData(rtfData, forType: .rtf)
            wroteContent = true
        }
        if let pdfData = item.pdfData {
            pasteboard.setData(pdfData, forType: .pdf)
            wroteContent = true
        }
        if let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .png)
            wroteContent = true
        }
        if let filenamesStr = item.filenames,
           let data = filenamesStr.data(using: .utf8),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            let urls = paths.compactMap { URL(fileURLWithPath: $0) as NSURL }
            pasteboard.writeObjects(urls)
            wroteContent = true
        }
        if let stringValue = item.stringValue {
            pasteboard.setString(stringValue, forType: .string)
            wroteContent = true
        }

        return wroteContent ? pasteboard.changeCount : nil
    }

    func paste() {
        guard accessibilityService.isAccessibilityEnabled(prompt: true) else { return }

        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
