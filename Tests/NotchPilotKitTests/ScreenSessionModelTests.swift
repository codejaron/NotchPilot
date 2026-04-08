import CoreGraphics
import XCTest
@testable import NotchPilotKit

@MainActor
final class ScreenSessionModelTests: XCTestCase {
    func testInteractiveSneakPeekAutoOpensAndReturnsToSneakPeekWhenClosed() {
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
        XCTAssertEqual(session.notchState, .open)
        XCTAssertFalse(session.showsSneakPeekOverlay)

        session.close()
        XCTAssertEqual(session.notchState, .sneakPeek)
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
        XCTAssertEqual(session.notchState, .closed)

        try? await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(session.notchState, .open)

        session.setHover(false, fallbackPluginID: "ai")
        try? await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(session.notchState, .closed)
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

        XCTAssertEqual(session.notchState, .sneakPeek)
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

        XCTAssertEqual(session.notchState, .sneakPeek)

        session.setHover(true, fallbackPluginID: "ai")
        try? await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(session.notchState, .open)
    }
}
