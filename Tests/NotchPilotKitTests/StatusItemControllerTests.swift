import AppKit
import XCTest
@testable import NotchPilotKit

final class StatusItemControllerTests: XCTestCase {
    @MainActor
    func testStatusItemMenuIncludesLyricsActionsBeforeSettings() {
        let controller = StatusItemController(
            openHandler: {},
            closeHandler: {},
            searchLyricsHandler: {},
            ignoreCurrentTrackLyricsHandler: {},
            revealCurrentLyricsInFinderHandler: {},
            canSearchCurrentTrackLyrics: { true },
            canIgnoreCurrentTrackLyrics: { true },
            canRevealCurrentLyricsInFinder: { true },
            settingsHandler: {},
            quitHandler: {}
        )

        XCTAssertEqual(
            controller.menuItemTitlesForTesting,
            [
                "Open on Active Screen",
                "Close All",
                "Search Lyrics…",
                "Mark Current Lyrics as Wrong",
                "Reveal Lyrics Cache in Finder",
                "",
                "Settings…",
                "Quit NotchPilot",
            ]
        )
    }

    @MainActor
    func testStatusItemMenuDisablesLyricsActionsWhenUnavailable() throws {
        let controller = StatusItemController(
            openHandler: {},
            closeHandler: {},
            searchLyricsHandler: {},
            ignoreCurrentTrackLyricsHandler: {},
            revealCurrentLyricsInFinderHandler: {},
            canSearchCurrentTrackLyrics: { false },
            canIgnoreCurrentTrackLyrics: { false },
            canRevealCurrentLyricsInFinder: { false },
            settingsHandler: {},
            quitHandler: {}
        )

        let menuItems = controller.menuItemsForTesting
        let searchItem = try XCTUnwrap(menuItems.first(where: { $0.title == "Search Lyrics…" }))
        let ignoreItem = try XCTUnwrap(menuItems.first(where: { $0.title == "Mark Current Lyrics as Wrong" }))
        let revealItem = try XCTUnwrap(menuItems.first(where: { $0.title == "Reveal Lyrics Cache in Finder" }))

        XCTAssertFalse(controller.validateMenuItem(searchItem))
        XCTAssertFalse(controller.validateMenuItem(ignoreItem))
        XCTAssertFalse(controller.validateMenuItem(revealItem))
    }
}
