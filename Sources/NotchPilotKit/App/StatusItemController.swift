import AppKit

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let openHandler: () -> Void
    private let closeHandler: () -> Void
    private let quitHandler: () -> Void

    public init(
        openHandler: @escaping () -> Void,
        closeHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.openHandler = openHandler
        self.closeHandler = closeHandler
        self.quitHandler = quitHandler
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "capsule.bottomhalf.filled", accessibilityDescription: "NotchPilot")
            button.imagePosition = .imageLeading
            button.title = "NotchPilot"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open on Active Screen", action: #selector(openAI), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Close All", action: #selector(closeAll), keyEquivalent: "w"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchPilot", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func openAI() {
        openHandler()
    }

    @objc private func closeAll() {
        closeHandler()
    }

    @objc private func quit() {
        quitHandler()
    }
}
