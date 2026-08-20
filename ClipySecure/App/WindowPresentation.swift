import AppKit

/// ClipySecure ships as an `LSUIElement` app, so it launches with the
/// `.accessory` activation policy: no Dock icon, no Cmd-Tab entry, and — since
/// macOS 14 made activation cooperative — no reliable way to raise its own
/// windows above whatever app is currently frontmost. `NSApp.activate()` alone
/// is a request the system is free to ignore, so a window shown from an
/// accessory app opens silently *behind* everything the user has open.
///
/// Any window the user is meant to actually see therefore promotes the app to
/// `.regular` for as long as that window is open. Promotions are reference
/// counted so closing one window while another is still open doesn't demote the
/// app out from under the survivor.
@MainActor
enum ActivationPolicyManager {
    private static var promotionCount = 0

    /// Promote to `.regular` (Dock icon + Cmd-Tab). Every call must be balanced
    /// by `endWindowSession()`, or the app will never return to the menu bar.
    static func beginWindowSession() {
        promotionCount += 1
        if promotionCount == 1 {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// Demote back to `.accessory` once the last promoted window has closed.
    static func endWindowSession() {
        promotionCount = max(0, promotionCount - 1)
        if promotionCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension NSWindow {
    /// Installs `controller` as the content view controller, applies `size`, and
    /// only then centers the window.
    ///
    /// Order matters. Assigning `contentViewController` resizes the window to the
    /// hosting controller's fitting size, and a SwiftUI view containing
    /// `maxWidth: .infinity` reports a fitting width as wide as the display.
    /// AppKit clamps that oversized window to the screen, and the subsequent
    /// shrink back down is anchored at the top-left — which leaves the window
    /// pinned to the top of the screen, underneath the menu bar (or any
    /// third-party status bar drawn there). Centering last makes the final
    /// position independent of that intermediate size.
    func setCenteredContent(_ controller: NSViewController, size: NSSize) {
        contentViewController = controller
        setContentSize(size)
        center()
    }

    /// Brings the window forward on the next run loop tick.
    ///
    /// Display is deferred because assigning `contentViewController` triggers a
    /// SwiftUI layout pass; ordering the window front in the same tick triggers a
    /// second pass and recurses on macOS 26. The deferral also gives a preceding
    /// `setActivationPolicy(.regular)` a run loop turn to take effect.
    ///
    /// Activation comes first: ordering a window front while the app is still
    /// inactive only places it at the top of *its own* layer, which leaves it
    /// beneath the frontmost app's windows. Activating first makes this app
    /// current, so the subsequent order-front is genuinely on top.
    func presentDeferred() {
        Task { @MainActor in
            NSApp.activate()
            makeKeyAndOrderFront(nil)
        }
    }
}
