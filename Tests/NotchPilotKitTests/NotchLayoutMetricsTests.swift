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

        XCTAssertEqual(metrics.displaySize.width, 720, accuracy: 0.1)
        XCTAssertEqual(metrics.displaySize.height, 240, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.width, 720, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.height, 240, accuracy: 0.1)
    }

    func testExpandedPluginViewportIsOwnedByShellChrome() {
        let viewportHeight = NotchExpandedLayout.pluginViewportHeight(forDisplayHeight: 240)

        XCTAssertEqual(viewportHeight, 186, accuracy: 0.1)
        XCTAssertEqual(NotchExpandedLayout.safeHorizontalPadding, 27, accuracy: 0.1)
    }

    func testExpandedPluginTabsUseCompactShellOwnedSize() {
        XCTAssertEqual(NotchExpandedLayout.pluginTabSize.width, 34, accuracy: 0.1)
        XCTAssertEqual(NotchExpandedLayout.pluginTabSize.height, 24, accuracy: 0.1)
        XCTAssertEqual(NotchExpandedLayout.pluginTabIconSize, 13, accuracy: 0.1)
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

    func testPreviewClosedUsesWinningPluginPreviewHeight() {
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
                LayoutTestPlugin(id: "codex", previewPriority: 0, previewWidth: 360, previewHeight: 72),
            ]
        )

        XCTAssertEqual(metrics.displaySize.width, 360, accuracy: 0.1)
        XCTAssertEqual(metrics.displaySize.height, 72, accuracy: 0.1)
        XCTAssertEqual(metrics.interactionSize.height, 82, accuracy: 0.1)
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
    private let fixedPreviewHeight: CGFloat?

    init(
        id: String = "layout-test",
        previewPriority: Int? = nil,
        previewWidth: CGFloat? = nil,
        previewHeight: CGFloat? = nil
    ) {
        self.id = id
        self.previewPriority = previewPriority
        self.fixedPreviewWidth = previewWidth
        self.fixedPreviewHeight = previewHeight
    }

    func preview(context: NotchContext) -> NotchPluginPreview? {
        guard let fixedPreviewWidth else {
            return nil
        }

        return NotchPluginPreview(width: fixedPreviewWidth, height: fixedPreviewHeight, view: AnyView(EmptyView()))
    }

    func contentView(context: NotchContext) -> AnyView {
        AnyView(EmptyView())
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}
