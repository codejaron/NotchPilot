import XCTest
@testable import NotchPilotKit

@MainActor
final class NotchTabNavigatorTests: XCTestCase {
    func testNextWrapsUsingHeaderOrder() {
        let tabIDs = ["media-playback", "ai", "system-monitor"]

        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: "media-playback",
                orderedTabIDs: tabIDs,
                direction: .next
            ),
            "ai"
        )
        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: "system-monitor",
                orderedTabIDs: tabIDs,
                direction: .next
            ),
            "media-playback"
        )
    }

    func testPreviousWrapsUsingHeaderOrder() {
        let tabIDs = ["media-playback", "ai", "system-monitor"]

        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: "ai",
                orderedTabIDs: tabIDs,
                direction: .previous
            ),
            "media-playback"
        )
        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: "media-playback",
                orderedTabIDs: tabIDs,
                direction: .previous
            ),
            "system-monitor"
        )
    }

    func testLegacyAIPluginIDsResolveToVirtualAITab() {
        let tabIDs = ["media-playback", "ai", "system-monitor"]

        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: "codex",
                orderedTabIDs: tabIDs,
                direction: .next
            ),
            "system-monitor"
        )
        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: "claude",
                orderedTabIDs: tabIDs,
                direction: .previous
            ),
            "media-playback"
        )
    }

    func testMissingCurrentTabFallsBackToFirstAvailableTab() {
        let tabIDs = ["media-playback", "ai", "system-monitor"]

        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: "disabled-plugin",
                orderedTabIDs: tabIDs,
                direction: .next
            ),
            "media-playback"
        )
        XCTAssertEqual(
            NotchTabNavigator.destination(
                from: nil,
                orderedTabIDs: tabIDs,
                direction: .previous
            ),
            "media-playback"
        )
    }

    func testSingleTabDoesNotProduceGestureDestination() {
        XCTAssertNil(
            NotchTabNavigator.destination(
                from: "media-playback",
                orderedTabIDs: ["media-playback"],
                direction: .next
            )
        )
    }

    func testOrderedTabIDsInsertVirtualAIByDockOrder() {
        let tabIDs = NotchTabNavigator.orderedTabIDs(
            pluginTabs: [
                NotchTabNavigator.Tab(id: "system-monitor", title: "System", dockOrder: 120),
                NotchTabNavigator.Tab(id: "media-playback", title: "Media", dockOrder: 80),
                NotchTabNavigator.Tab(id: "notifications", title: "Notifications", dockOrder: 90),
            ],
            aiTabDockOrder: 100
        )

        XCTAssertEqual(tabIDs, ["media-playback", "notifications", "ai", "system-monitor"])
    }
}
