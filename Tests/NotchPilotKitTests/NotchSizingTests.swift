import CoreGraphics
import XCTest
@testable import NotchPilotKit

final class NotchSizingTests: XCTestCase {
    func testClosedCompactSizeMatchesRealNotchWidthAndSafeAreaHeight() {
        let size = NotchSizing.closedCompactSize(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 640, height: 38),
            auxiliaryTopRightArea: CGRect(x: 872, y: 944, width: 640, height: 38),
            safeAreaTopInset: 38,
            menuBarHeight: 38
        )

        XCTAssertEqual(size.width, 236, accuracy: 0.1)
        XCTAssertEqual(size.height, 38, accuracy: 0.1)
    }

    func testClosedCompactSizeUsesMenuBarHeightOnNonNotchDisplays() {
        let size = NotchSizing.closedCompactSize(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            safeAreaTopInset: 0,
            menuBarHeight: 24
        )

        XCTAssertEqual(size.width, 185, accuracy: 0.1)
        XCTAssertEqual(size.height, 24, accuracy: 0.1)
    }
}
