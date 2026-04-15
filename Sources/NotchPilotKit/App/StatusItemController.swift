import AppKit

@MainActor
public final class StatusItemController: NSObject, NSMenuItemValidation {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let openHandler: () -> Void
    private let closeHandler: () -> Void
    private let searchLyricsHandler: () -> Void
    private let ignoreCurrentTrackLyricsHandler: () -> Void
    private let revealCurrentLyricsInFinderHandler: () -> Void
    private let settingsHandler: () -> Void
    private let quitHandler: () -> Void
    private let canSearchCurrentTrackLyrics: () -> Bool
    private let canIgnoreCurrentTrackLyrics: () -> Bool
    private let canRevealCurrentLyricsInFinder: () -> Bool
    private let menu: NSMenu

    public init(
        openHandler: @escaping () -> Void,
        closeHandler: @escaping () -> Void,
        searchLyricsHandler: @escaping () -> Void,
        ignoreCurrentTrackLyricsHandler: @escaping () -> Void,
        revealCurrentLyricsInFinderHandler: @escaping () -> Void,
        canSearchCurrentTrackLyrics: @escaping () -> Bool,
        canIgnoreCurrentTrackLyrics: @escaping () -> Bool,
        canRevealCurrentLyricsInFinder: @escaping () -> Bool,
        settingsHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.openHandler = openHandler
        self.closeHandler = closeHandler
        self.searchLyricsHandler = searchLyricsHandler
        self.ignoreCurrentTrackLyricsHandler = ignoreCurrentTrackLyricsHandler
        self.revealCurrentLyricsInFinderHandler = revealCurrentLyricsInFinderHandler
        self.canSearchCurrentTrackLyrics = canSearchCurrentTrackLyrics
        self.canIgnoreCurrentTrackLyrics = canIgnoreCurrentTrackLyrics
        self.canRevealCurrentLyricsInFinder = canRevealCurrentLyricsInFinder
        self.settingsHandler = settingsHandler
        self.quitHandler = quitHandler
        self.menu = NSMenu()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "capsule.bottomhalf.filled", accessibilityDescription: "NotchPilot")
            button.imagePosition = .imageLeading
            button.title = "NotchPilot"
        }

        menu.addItem(NSMenuItem(title: "Open on Active Screen", action: #selector(openAI), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Close All", action: #selector(closeAll), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Search Lyrics…", action: #selector(searchLyrics), keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Mark Current Lyrics as Wrong",
                action: #selector(ignoreCurrentTrackLyrics),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Reveal Lyrics Cache in Finder",
                action: #selector(revealCurrentLyricsInFinder),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
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

    @objc private func searchLyrics() {
        searchLyricsHandler()
    }

    @objc private func ignoreCurrentTrackLyrics() {
        ignoreCurrentTrackLyricsHandler()
    }

    @objc private func revealCurrentLyricsInFinder() {
        revealCurrentLyricsInFinderHandler()
    }

    @objc private func openSettings() {
        settingsHandler()
    }

    @objc private func quit() {
        quitHandler()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(searchLyrics):
            return canSearchCurrentTrackLyrics()
        case #selector(ignoreCurrentTrackLyrics):
            return canIgnoreCurrentTrackLyrics()
        case #selector(revealCurrentLyricsInFinder):
            return canRevealCurrentLyricsInFinder()
        default:
            return true
        }
    }

    var menuItemTitlesForTesting: [String] {
        menu.items.map(\.title)
    }

    var menuItemsForTesting: [NSMenuItem] {
        menu.items
    }
}
