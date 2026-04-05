import LaunchAtLogin
import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentPage {
                case 0: welcomePage
                case 1: permissionsPage
                case 2: clipboardAccessPage
                default: readyPage
                }
            }
            .frame(maxWidth: .infinity, minHeight: 340)

            Divider()

            HStack {
                if currentPage > 0 {
                    Button(String(localized: "Back")) {
                        withAnimation { currentPage -= 1 }
                    }
                    .fixedSize()
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentPage < 3 {
                    Button(String(localized: "Next")) {
                        withAnimation { currentPage += 1 }
                    }
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(String(localized: "Get Started")) {
                        onComplete()
                    }
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "paperclip.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to ClipySecure")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("A privacy-first clipboard manager for macOS. Your clipboard history is stored locally and encrypted — never sent anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
        .padding(40)
    }

    private var permissionsPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("ClipySecure needs Accessibility permission to automatically paste items when you select them from the menu.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            Button(String(localized: "Open Accessibility Settings")) {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.large)
        }
        .padding(40)
    }

    private var clipboardAccessPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Clipboard Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("On macOS 14 and later, you may see a system prompt asking to allow ClipySecure to access the clipboard. Please allow this so the app can monitor and store your clipboard history.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
        .padding(40)
    }

    private var readyPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("ClipySecure will run in the menu bar. Use Cmd+Shift+V to open the clipboard menu at any time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            LaunchAtLogin.Toggle(String(localized: "Launch at Login"))
                .padding(.top, 8)
        }
        .padding(40)
    }
}
