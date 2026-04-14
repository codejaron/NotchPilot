import XCTest
@testable import NotchPilotKit

final class MediaPlaybackLayoutTests: XCTestCase {
    func testExpandedMediaLayoutFitsInsidePluginViewport() {
        let viewportHeight = NotchExpandedLayout.pluginViewportHeight(forDisplayHeight: 240)
        let requiredHeight = MediaPlaybackExpandedLayout.estimatedContentHeight(titleLineCount: 2)

        XCTAssertLessThanOrEqual(requiredHeight, viewportHeight)
    }
}
