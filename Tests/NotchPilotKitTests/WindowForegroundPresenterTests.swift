import XCTest
@testable import NotchPilotKit

final class WindowForegroundPresenterTests: XCTestCase {
    func testPresentationStepsActivateAppBeforeOrderingInactiveWindowsFront() {
        XCTAssertEqual(
            NotchPilotWindowForegroundPresenter.presentationSteps(isApplicationActive: false),
            [.activateCurrentApplication, .orderFrontRegardless, .makeKeyAndOrderFront]
        )
    }

    func testPresentationStepsStillForceOrderFrontWhenAppIsAlreadyActive() {
        XCTAssertEqual(
            NotchPilotWindowForegroundPresenter.presentationSteps(isApplicationActive: true),
            [.orderFrontRegardless, .makeKeyAndOrderFront]
        )
    }
}
