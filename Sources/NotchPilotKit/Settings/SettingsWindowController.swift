import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?

    public init() {}

    public func showSettings(selectedPane: SettingsPane = .pluginsOverview) {
        if let window {
            window.contentView = NSHostingView(rootView: SettingsView(selectedPane: selectedPane))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchPilot Settings"
        window.contentView = NSHostingView(rootView: SettingsView(selectedPane: selectedPane))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
