import SwiftUI
import XCTest
@testable import NotchPilotKit

@MainActor
final class NotchLayoutMetricsTests: XCTestCase {
    func testIdleClosedInteractionSizeUsesMinimalShellWidth() {
        let session = makeSession(closedNotchSize: CGSize(width: 236, height: 38))

        let metrics = NotchLayoutMetrics.resolve(
            session: session,
            plugins: [LayoutTestPlugin(previewWidth: 360)]
        )

        XCTAssertEqual(metrics.displaySize.width, 236, accuracy: 0.1)
        XCTAssertEqual(metrics.displaySize.height, 38, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.width, 296, accuracy: 0.1)
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

    func testPreviewClosedUsesWinningPluginPreviewWidth() {
        let session = makeSession(closedNotchSize: CGSize(width: 236, height: 38))
        session.enqueue(
            SneakPeekRequest(
                pluginID: "codex",
                priority: 0,
                target: .activeScreen,
                isInteractive: false,
                autoDismissAfter: nil
            )
        )

        let metrics = NotchLayoutMetrics.resolve(
            session: session,
            plugins: [
                LayoutTestPlugin(id: "claude", previewPriority: 10, previewWidth: 320),
                LayoutTestPlugin(id: "codex", previewPriority: 0, previewWidth: 410),
            ]
        )

        XCTAssertEqual(metrics.displaySize.width, 410, accuracy: 0.1)
        XCTAssertEqual(metrics.displaySize.height, 38, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.width, 470, accuracy: 0.1)
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
    let id: String
    let title = "Layout Test"
    let iconSystemName = "ruler"
    let dockOrder = 1
    let accentColor: Color = .blue
    var isEnabled = true
    let previewPriority: Int?

    private let fixedPreviewWidth: CGFloat?

    init(id: String = "layout-test", previewPriority: Int? = nil, previewWidth: CGFloat? = nil) {
        self.id = id
        self.previewPriority = previewPriority
        self.fixedPreviewWidth = previewWidth
    }

    func preview(context: NotchContext) -> NotchPluginPreview? {
        guard let fixedPreviewWidth else {
            return nil
        }

        return NotchPluginPreview(width: fixedPreviewWidth, view: AnyView(EmptyView()))
    }

    func contentView(context: NotchContext) -> AnyView {
        AnyView(EmptyView())
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}
