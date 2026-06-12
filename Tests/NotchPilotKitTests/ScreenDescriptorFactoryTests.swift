import CoreGraphics
import XCTest
@testable import NotchPilotKit

final class ScreenDescriptorFactoryTests: XCTestCase {
    func testDescriptorCanIncludeClosedNotchSize() {
        let descriptor = ScreenDescriptorFactory.descriptor(
            id: "primary",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 958),
            isPrimary: true,
            includeClosedNotchSize: true
        )

        XCTAssertEqual(descriptor.id, "primary")
        XCTAssertTrue(descriptor.isPrimary)
        XCTAssertNotNil(descriptor.closedNotchSize)
    }

    func testDescriptorCanOmitClosedNotchSize() {
        let descriptor = ScreenDescriptorFactory.descriptor(
            id: "secondary",
            frame: CGRect(x: 1512, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 1512, y: 0, width: 1440, height: 876),
            isPrimary: false,
            includeClosedNotchSize: false
        )

        XCTAssertEqual(descriptor.id, "secondary")
        XCTAssertFalse(descriptor.isPrimary)
        XCTAssertNil(descriptor.closedNotchSize)
    }
}
