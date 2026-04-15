import CoreGraphics
import XCTest
@testable import NotchPilotKit

final class DesktopLyricsWindowLayoutTests: XCTestCase {
    func testWindowFrameIsPinnedToVisibleFrameBottomCenter() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let cardSize = CGSize(width: 420, height: 88)

        let frame = DesktopLyricsWindowLayout.frame(for: cardSize, in: visibleFrame)

        XCTAssertEqual(frame.width, 420, accuracy: 0.1)
        XCTAssertEqual(frame.height, 88, accuracy: 0.1)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.1)
        XCTAssertGreaterThan(frame.minY, visibleFrame.minY)
        XCTAssertLessThan(frame.maxY, visibleFrame.maxY)
    }

    func testActiveScreenResolverReturnsDescriptorContainingMouseLocation() {
        let descriptors = [
            ScreenDescriptor(
                id: "left",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                isPrimary: true,
                closedNotchSize: nil
            ),
            ScreenDescriptor(
                id: "right",
                frame: CGRect(x: 800, y: 0, width: 800, height: 600),
                isPrimary: false,
                closedNotchSize: nil
            ),
        ]

        let resolved = ActiveDesktopLyricsScreenResolver.resolve(
            mouseLocation: CGPoint(x: 1000, y: 300),
            descriptors: descriptors
        )

        XCTAssertEqual(resolved, "right")
    }
}
