import XCTest
@testable import NotchPilotKit

final class PresentationTargetResolverTests: XCTestCase {
    func testActiveScreenResolvesToPointerScreen() {
        let screens = [
            ScreenDescriptor(id: "left", frame: .init(x: 0, y: 0, width: 1920, height: 1080), isPrimary: false),
            ScreenDescriptor(id: "right", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: true),
        ]
        let context = ScreenResolutionContext(
            connectedScreens: screens,
            activeScreenID: "right",
            primaryScreenID: "left"
        )

        XCTAssertEqual(PresentationTargetResolver.resolve(.activeScreen, in: context), ["right"])
    }

    func testPrimaryScreenFallsBackToActiveScreenThenFirstConnectedScreen() {
        let screens = [
            ScreenDescriptor(id: "left", frame: .init(x: 0, y: 0, width: 1920, height: 1080), isPrimary: false),
            ScreenDescriptor(id: "right", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: true),
        ]

        let missingPrimary = ScreenResolutionContext(
            connectedScreens: screens,
            activeScreenID: "right",
            primaryScreenID: nil
        )
        XCTAssertEqual(PresentationTargetResolver.resolve(.primaryScreen, in: missingPrimary), ["right"])

        let noPrimaryOrActive = ScreenResolutionContext(
            connectedScreens: screens,
            activeScreenID: nil,
            primaryScreenID: nil
        )
        XCTAssertEqual(PresentationTargetResolver.resolve(.primaryScreen, in: noPrimaryOrActive), ["left"])
    }

    func testSpecificScreenFallsBackUsingTheSameResolutionRules() {
        let screens = [
            ScreenDescriptor(id: "only", frame: .init(x: 0, y: 0, width: 1440, height: 900), isPrimary: true),
        ]
        let context = ScreenResolutionContext(
            connectedScreens: screens,
            activeScreenID: nil,
            primaryScreenID: nil
        )

        XCTAssertEqual(PresentationTargetResolver.resolve(.screen(id: "missing"), in: context), ["only"])
    }
}
