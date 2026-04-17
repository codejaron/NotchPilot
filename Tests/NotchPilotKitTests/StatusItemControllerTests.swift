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
            canAdjustLyricsOffset: { false },
            getLyricsOffset: { 0 },
            setLyricsOffset: { _ in },
            settingsHandler: {},
            quitHandler: {}
        )

        let titles = controller.menuItemTitlesForTesting
        XCTAssertTrue(titles.contains("Open on Active Screen"))
        XCTAssertTrue(titles.contains("Close All"))
        XCTAssertTrue(titles.contains("Search Lyrics…"))
        XCTAssertTrue(titles.contains("Mark Current Lyrics as Wrong"))
        XCTAssertTrue(titles.contains("Reveal Lyrics Cache in Finder"))
        XCTAssertTrue(titles.contains("Settings…"))
        XCTAssertTrue(titles.contains("Quit NotchPilot"))
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
            canAdjustLyricsOffset: { false },
            getLyricsOffset: { 0 },
            setLyricsOffset: { _ in },
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
