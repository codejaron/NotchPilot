import SwiftUI
import XCTest
@testable import NotchPilotKit

@MainActor
final class NotchLayoutMetricsTests: XCTestCase {
    func testClosedInteractionSizeTracksCompactContentWidth() {
        let session = makeSession(closedNotchSize: CGSize(width: 236, height: 38))

        let metrics = NotchLayoutMetrics.resolve(
            session: session,
            plugins: [LayoutTestPlugin(compactWidth: 360)]
        )

        XCTAssertEqual(metrics.displaySize.width, 360, accuracy: 0.1)
        XCTAssertEqual(metrics.displaySize.height, 38, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.width, 420, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.height, 48, accuracy: 0.1)
    }

    func testOpenInteractionSizeMatchesExpandedContent() {
        let session = makeSession(closedNotchSize: CGSize(width: 236, height: 38))
        session.open(pluginID: "ai")

        let metrics = NotchLayoutMetrics.resolve(session: session, plugins: [LayoutTestPlugin()])

        XCTAssertEqual(metrics.displaySize.width, 520, accuracy: 0.1)
        XCTAssertEqual(metrics.displaySize.height, 320, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.width, 520, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.height, 320, accuracy: 0.1)
    }

    func testClosedInteractionFrameIsPinnedToTopCenterOfWindow() {
        let session = makeSession(closedNotchSize: CGSize(width: 236, height: 38))
        let metrics = NotchLayoutMetrics.resolve(session: session, plugins: [LayoutTestPlugin()])

        let interactionFrame = session.interactionFrame(for: metrics.interactionSize)

        XCTAssertEqual(interactionFrame.width, 296, accuracy: 0.1)
        XCTAssertEqual(interactionFrame.height, 48, accuracy: 0.1)
        XCTAssertEqual(interactionFrame.midX, session.windowFrame.midX, accuracy: 0.1)
        XCTAssertEqual(interactionFrame.maxY, session.windowFrame.maxY, accuracy: 0.1)
    }

    private func makeSession(closedNotchSize: CGSize) -> ScreenSessionModel {
        ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true,
                closedNotchSize: closedNotchSize
            )
        )
    }
}

@MainActor
private final class LayoutTestPlugin: NotchPlugin {
    let id = "layout-test"
    let name = "Layout Test"
    let iconSystemName = "ruler"
    let priority = 1
    var isEnabled = true

    private let fixedCompactWidth: CGFloat?

    init(compactWidth: CGFloat? = nil) {
        self.fixedCompactWidth = compactWidth
    }

    func compactView(context: NotchContext) -> AnyView? {
        AnyView(EmptyView())
    }

    func compactWidth(context: NotchContext) -> CGFloat? {
        fixedCompactWidth
    }

    func sneakPeekView(context: NotchContext) -> AnyView? {
        nil
    }

    func sneakPeekWidth(context: NotchContext) -> CGFloat? {
        nil
    }

    func expandedView(context: NotchContext) -> AnyView {
        AnyView(EmptyView())
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}
