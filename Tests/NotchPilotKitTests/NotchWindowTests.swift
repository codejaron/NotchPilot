import CoreGraphics
import AppKit
import XCTest
@testable import NotchPilotKit

final class NotchWindowTests: XCTestCase {
    func testDefaultStyleMaskDoesNotRequestSystemHUDChrome() {
        let styleMask = NotchWindowStyle.defaultStyleMask

        XCTAssertTrue(styleMask.contains(.borderless))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(styleMask.contains(.utilityWindow))
        XCTAssertFalse(styleMask.contains(.hudWindow))
    }

    func testFrameRefreshPlanSkipsWindowUpdateWhenTargetFrameIsUnchanged() {
        let frame = CGRect(x: 100, y: 200, width: 520, height: 340)

        let plan = NotchWindowFrameRefreshPlan.resolve(currentFrame: frame, targetFrame: frame)

        XCTAssertFalse(plan.needsWindowFrameUpdate)
        XCTAssertEqual(plan.targetFrame, frame)
    }

    func testFrameRefreshPlanUpdatesWindowWhenTargetFrameChanges() {
        let currentFrame = CGRect(x: 100, y: 200, width: 520, height: 340)
        let targetFrame = CGRect(x: 120, y: 210, width: 600, height: 340)

        let plan = NotchWindowFrameRefreshPlan.resolve(currentFrame: currentFrame, targetFrame: targetFrame)

        XCTAssertTrue(plan.needsWindowFrameUpdate)
        XCTAssertEqual(plan.targetFrame, targetFrame)
    }
}
