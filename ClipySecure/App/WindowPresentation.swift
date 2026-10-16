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
    ///
    /// Cooperative activation on macOS 14+ can refuse an accessory app's request
    /// outright — a global hotkey plus a detached menu does not reliably count as
    /// the user interacting with *this* app. When it refuses, `makeKeyAndOrderFront`
    /// raises the window only within our own inactive layer, i.e. behind the
    /// frontmost app. The fallback floats the window above everything until it
    /// actually becomes key, then drops it back to a normal level so it behaves
    /// like an ordinary window from then on. The collection behaviour makes the
    /// window follow the user to the active Space (including a full-screen app's
    /// own Space) rather than staying pinned where it first appeared.
    func presentDeferred() {
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        Task { @MainActor in
            NSApp.activate()
            makeKeyAndOrderFront(nil)
            guard !NSApp.isActive else { return }
            floatUntilKey()
        }
    }

    /// Floats the window above the frontmost app until it becomes key, then
    /// returns it to `.normal`. Used only when cooperative activation is refused.
    private func floatUntilKey() {
        level = .floating
        let box = ObserverBox()
        box.token = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.level = .normal
            }
            if let token = box.token {
                NotificationCenter.default.removeObserver(token)
                box.token = nil
            }
        }
    }
}

/// Holds a one-shot notification token so the observer block can remove itself.
/// `@unchecked Sendable` is sound here: the box is only ever touched on the main
/// thread (the observer is registered with `queue: .main`).
private final class ObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}
