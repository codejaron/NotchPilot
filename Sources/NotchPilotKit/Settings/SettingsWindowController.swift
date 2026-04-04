import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?

    public init() {}

    public func showSettings(selectedTab: SettingsView.Tab = .aiHooks) {
        if let window {
            window.contentView = NSHostingView(rootView: SettingsView(selectedTab: selectedTab))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchPilot Settings"
        window.contentView = NSHostingView(rootView: SettingsView(selectedTab: selectedTab))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
