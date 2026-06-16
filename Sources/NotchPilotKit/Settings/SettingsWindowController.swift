import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?

    public init() {}

    public func showSettings(selectedPane: SettingsPane = .general) {
        if let window {
            Self.configure(window: window)
            window.contentView = NSHostingView(rootView: SettingsView(selectedPane: selectedPane))
            NotchPilotWindowForegroundPresenter.present(window)
            return
        }

        let window = Self.makeWindow(rootView: SettingsView(selectedPane: selectedPane))
        window.center()
        window.isReleasedWhenClosed = false
        NotchPilotWindowForegroundPresenter.present(window)

        self.window = window
    }

    static func makeWindow<Content: View>(rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        configure(window: window)
        window.setContentSize(NSSize(width: 960, height: 620))
        window.minSize = NSSize(width: 900, height: 580)
        window.contentView = NSHostingView(rootView: rootView)
        return window
    }

    private static func configure(window: NSWindow) {
        window.title = AppStrings.text(
            .settingsWindowTitle,
            language: SettingsStore.shared.general.interfaceLanguage
        )
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
    }
}
