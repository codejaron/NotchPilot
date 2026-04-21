import AppKit
import XCTest
@testable import NotchPilotKit

final class StatusItemControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "StatusItemControllerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    @MainActor
    func testStatusItemUsesIconOnlyNotchedComputerMark() throws {
        let controller = makeController()

        let statusItem = try XCTUnwrap(statusItem(from: controller))
        XCTAssertEqual(statusItem.length, NSStatusItem.squareLength)

        let button = try XCTUnwrap(statusButton(from: controller))
        XCTAssertEqual(button.title, "")
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.image?.isTemplate, true)
        XCTAssertEqual(button.imageScaling, .scaleProportionallyDown)
    }

    @MainActor
    func testStatusItemMenuIncludesLyricsActionsBeforeSettings() {
        let controller = makeController()

        let titles = controller.menuItemTitlesForTesting
        XCTAssertFalse(titles.contains("Open on Active Screen"))
        XCTAssertFalse(titles.contains("Close All"))
        XCTAssertTrue(titles.contains("Search Lyrics…"))
        XCTAssertTrue(titles.contains("Mark Current Lyrics as Wrong"))
        XCTAssertTrue(titles.contains("Reveal Lyrics Cache in Finder"))
        XCTAssertTrue(titles.contains("Hide All Sneaks"))
        XCTAssertTrue(titles.contains("Settings…"))
        XCTAssertTrue(titles.contains("Quit NotchPilot"))
    }

    @MainActor
    func testStatusItemMenuUsesConfiguredLanguageAndUpdatesWhenLanguageChanges() {
        let store = SettingsStore(defaults: defaults)
        store.interfaceLanguage = .english
        let controller = makeController(settingsStore: store)

        XCTAssertTrue(controller.menuItemTitlesForTesting.contains("Search Lyrics…"))
        XCTAssertTrue(controller.menuItemTitlesForTesting.contains("Settings…"))

        store.interfaceLanguage = .zhHans

        XCTAssertTrue(controller.menuItemTitlesForTesting.contains("搜索歌词…"))
        XCTAssertTrue(controller.menuItemTitlesForTesting.contains("设置…"))
        XCTAssertTrue(controller.menuItemTitlesForTesting.contains("退出 NotchPilot"))
    }

    @MainActor
    func testStatusItemMenuDisablesLyricsActionsWhenUnavailable() throws {
        let controller = makeController(
            canSearchCurrentTrackLyrics: { false },
            canIgnoreCurrentTrackLyrics: { false },
            canRevealCurrentLyricsInFinder: { false }
        )

        let menuItems = controller.menuItemsForTesting
        let searchItem = try XCTUnwrap(menuItems.first(where: { $0.title == "Search Lyrics…" }))
        let ignoreItem = try XCTUnwrap(menuItems.first(where: { $0.title == "Mark Current Lyrics as Wrong" }))
        let revealItem = try XCTUnwrap(menuItems.first(where: { $0.title == "Reveal Lyrics Cache in Finder" }))

        XCTAssertFalse(controller.validateMenuItem(searchItem))
        XCTAssertFalse(controller.validateMenuItem(ignoreItem))
        XCTAssertFalse(controller.validateMenuItem(revealItem))
    }

    @MainActor
    func testActivitySneakToggleUsesShortcutAndReflectsMenuState() throws {
        var activitySneaksHidden = false
        let controller = makeController(
            isActivitySneakPreviewsHidden: { activitySneaksHidden },
            toggleActivitySneakPreviewsHandler: { activitySneaksHidden.toggle() }
        )

        let hideSneaksItem = try XCTUnwrap(
            controller.menuItemsForTesting.first(where: { $0.title == "Hide All Sneaks" })
        )

        XCTAssertEqual(hideSneaksItem.keyEquivalent, "s")
        XCTAssertTrue(hideSneaksItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(hideSneaksItem.keyEquivalentModifierMask.contains(.shift))

        controller.menuWillOpen(NSMenu())
        XCTAssertEqual(hideSneaksItem.state, .off)

        activitySneaksHidden = true
        controller.menuWillOpen(NSMenu())
        XCTAssertEqual(hideSneaksItem.state, .on)
    }

    @MainActor
    func testActivitySneakToggleActionUpdatesSetting() throws {
        var activitySneaksHidden = false
        let controller = makeController(
            isActivitySneakPreviewsHidden: { activitySneaksHidden },
            toggleActivitySneakPreviewsHandler: { activitySneaksHidden.toggle() }
        )

        let hideSneaksItem = try XCTUnwrap(
            controller.menuItemsForTesting.first(where: { $0.title == "Hide All Sneaks" })
        )
        let action = try XCTUnwrap(hideSneaksItem.action)

        XCTAssertTrue(NSApp.sendAction(action, to: hideSneaksItem.target, from: hideSneaksItem))
        XCTAssertTrue(activitySneaksHidden)
        XCTAssertEqual(hideSneaksItem.state, .on)
    }

    @MainActor
    private func makeController(
        canSearchCurrentTrackLyrics: @escaping () -> Bool = { true },
        canIgnoreCurrentTrackLyrics: @escaping () -> Bool = { true },
        canRevealCurrentLyricsInFinder: @escaping () -> Bool = { true },
        isActivitySneakPreviewsHidden: @escaping () -> Bool = { false },
        toggleActivitySneakPreviewsHandler: @escaping () -> Void = {},
        settingsStore: SettingsStore? = nil
    ) -> StatusItemController {
        let resolvedSettingsStore: SettingsStore
        if let settingsStore {
            resolvedSettingsStore = settingsStore
        } else {
            resolvedSettingsStore = SettingsStore(defaults: defaults)
            resolvedSettingsStore.interfaceLanguage = .english
        }

        return StatusItemController(
            searchLyricsHandler: {},
            ignoreCurrentTrackLyricsHandler: {},
            revealCurrentLyricsInFinderHandler: {},
            canSearchCurrentTrackLyrics: canSearchCurrentTrackLyrics,
            canIgnoreCurrentTrackLyrics: canIgnoreCurrentTrackLyrics,
            canRevealCurrentLyricsInFinder: canRevealCurrentLyricsInFinder,
            canAdjustLyricsOffset: { false },
            getLyricsOffset: { 0 },
            setLyricsOffset: { _ in },
            isActivitySneakPreviewsHidden: isActivitySneakPreviewsHidden,
            toggleActivitySneakPreviewsHandler: toggleActivitySneakPreviewsHandler,
            settingsStore: resolvedSettingsStore,
            settingsHandler: {},
            quitHandler: {}
        )
    }

    private func statusButton(from controller: StatusItemController) -> NSStatusBarButton? {
        statusItem(from: controller)?.button
    }

    private func statusItem(from controller: StatusItemController) -> NSStatusItem? {
        let mirror = Mirror(reflecting: controller)
        return mirror.children.first { $0.label == "statusItem" }?.value as? NSStatusItem
    }
}
