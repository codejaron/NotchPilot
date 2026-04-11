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
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchPilot Settings"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 960, height: 620))
        window.minSize = NSSize(width: 900, height: 580)
        window.contentView = NSHostingView(rootView: SettingsView(selectedPane: selectedPane))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
