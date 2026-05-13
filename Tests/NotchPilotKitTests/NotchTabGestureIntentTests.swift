import XCTest
@testable import NotchPilotKit

final class NotchTabGestureIntentTests: XCTestCase {
    func testStrongLeftHorizontalMovementSelectsNextTab() {
        XCTAssertEqual(
            NotchTabGestureIntent.direction(
                horizontalDelta: -42,
                verticalDelta: 6,
                minimumHorizontalDelta: 28,
                horizontalDominanceRatio: 1.4
            ),
            .next
        )
    }

    func testStrongRightHorizontalMovementSelectsPreviousTab() {
        XCTAssertEqual(
            NotchTabGestureIntent.direction(
                horizontalDelta: 38,
                verticalDelta: 4,
                minimumHorizontalDelta: 28,
                horizontalDominanceRatio: 1.4
            ),
            .previous
        )
    }

    func testVerticalMovementDoesNotSwitchTabs() {
        XCTAssertNil(
            NotchTabGestureIntent.direction(
                horizontalDelta: 35,
                verticalDelta: 30,
                minimumHorizontalDelta: 28,
                horizontalDominanceRatio: 1.4
            )
        )
    }

    func testShortHorizontalMovementDoesNotSwitchTabs() {
        XCTAssertNil(
            NotchTabGestureIntent.direction(
                horizontalDelta: -18,
                verticalDelta: 1,
                minimumHorizontalDelta: 28,
                horizontalDominanceRatio: 1.4
            )
        )
    }
}
