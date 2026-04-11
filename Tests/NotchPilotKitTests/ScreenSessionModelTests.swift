import CoreGraphics
import XCTest
@testable import NotchPilotKit

@MainActor
final class ScreenSessionModelTests: XCTestCase {
    func testPreviewRequestKeepsSessionInPreviewClosedUntilHoverOpen() {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )

        let request = SneakPeekRequest(
            id: UUID(),
            pluginID: "ai",
            priority: 1000,
            target: .activeScreen,
            isInteractive: true,
            autoDismissAfter: nil
        )

        session.enqueue(request)
        XCTAssertEqual(session.notchState, .previewClosed)
        XCTAssertTrue(session.showsSneakPeekOverlay)

        session.setHover(true, fallbackPluginID: "claude")
        XCTAssertEqual(session.notchState, .previewClosed)

        let expectation = XCTestExpectation(description: "hover opens previewed plugin")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            XCTAssertEqual(session.notchState, .open)
            XCTAssertEqual(session.activePluginID, "ai")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        session.close()
        XCTAssertEqual(session.notchState, .previewClosed)
        XCTAssertTrue(session.showsSneakPeekOverlay)
    }

    func testWindowFrameUsesFixedExpandedWindowSizeAndStaysPinnedToTopCenter() {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true,
                closedNotchSize: CGSize(width: 236, height: 38)
            )
        )

        let frame = session.windowFrame

        XCTAssertEqual(frame.width, 520, accuracy: 0.1)
        XCTAssertEqual(frame.height, 340, accuracy: 0.1)
        XCTAssertEqual(frame.midX, 1512 / 2, accuracy: 0.1)
        XCTAssertEqual(frame.maxY, 982, accuracy: 0.1)

        session.enqueue(
            SneakPeekRequest(
                pluginID: "ai",
                priority: 1000,
                target: .activeScreen,
                isInteractive: true,
                autoDismissAfter: nil
            )
        )
        XCTAssertEqual(session.windowFrame, frame)

        session.open(pluginID: "ai")
        XCTAssertEqual(session.windowFrame, frame)
    }

    func testManualOpenDoesNotCloseOnHoverExit() async {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )

        session.toggleOpen(defaultPluginID: "ai")
        session.setHover(false, fallbackPluginID: "ai")

        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(session.notchState, .open)
    }

    func testHoverOpenClosesAfterExitDelay() async {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )

        session.setHover(true, fallbackPluginID: "ai")
        XCTAssertEqual(session.notchState, .idleClosed)
        XCTAssertTrue(session.hoverFeedbackTrigger)

        try? await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(session.notchState, .idleClosed)

        try? await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(session.notchState, .open)

        session.setHover(false, fallbackPluginID: "ai")
        try? await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(session.notchState, .idleClosed)
    }

    func testHoverOpenedApprovalReturnsToSneakPeekWhenPointerLeaves() async {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )

        session.enqueue(
            SneakPeekRequest(
                pluginID: "ai",
                priority: 1000,
                target: .activeScreen,
                isInteractive: true,
                autoDismissAfter: nil
            )
        )

        session.openForHover(pluginID: "ai")
        XCTAssertEqual(session.notchState, .open)

        session.setHover(false, fallbackPluginID: "ai")
        try? await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(session.notchState, .previewClosed)
        XCTAssertTrue(session.showsSneakPeekOverlay)
    }

    func testHoveringNonInteractiveSneakPeekOpensNotchWithoutClick() async {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )

        session.enqueue(
            SneakPeekRequest(
                pluginID: "ai",
                priority: 1000,
                target: .activeScreen,
                isInteractive: false,
                autoDismissAfter: nil
            )
        )

        XCTAssertEqual(session.notchState, .previewClosed)

        session.setHover(true, fallbackPluginID: "ai")
        try? await Task.sleep(for: .milliseconds(360))

        XCTAssertEqual(session.notchState, .open)
    }

    func testLastSelectedPluginWinsWhenOpeningWithoutPreview() async {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )

        session.open(pluginID: "codex")
        session.close()

        XCTAssertEqual(session.notchState, .idleClosed)
        XCTAssertEqual(session.activePluginID, "codex")

        session.setHover(true, fallbackPluginID: "claude")
        try? await Task.sleep(for: .milliseconds(360))

        XCTAssertEqual(session.notchState, .open)
        XCTAssertEqual(session.activePluginID, "codex")
    }
}
