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

    func testActivitySneakRequestsAreHiddenWhenGlobalSettingIsEnabled() {
        let store = makeSettingsStore(activitySneakPreviewsHidden: true)
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            ),
            settingsStore: store
        )

        session.enqueue(
            SneakPeekRequest(
                pluginID: "codex",
                priority: 1000,
                target: .activeScreen,
                kind: .activity,
                isInteractive: false,
                autoDismissAfter: nil
            )
        )

        XCTAssertEqual(session.notchState, .idleClosed)
        XCTAssertFalse(session.showsSneakPeekOverlay)

        store.activitySneakPreviewsHidden = false

        XCTAssertEqual(session.notchState, .previewClosed)
        XCTAssertEqual(session.currentSneakPeek?.pluginID, "codex")
    }

    func testAttentionSneakRequestsRemainVisibleWhenActivitySneaksAreHidden() {
        let store = makeSettingsStore(activitySneakPreviewsHidden: true)
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            ),
            settingsStore: store
        )

        session.enqueue(
            SneakPeekRequest(
                pluginID: "codex",
                priority: 1000,
                target: .activeScreen,
                kind: .attention,
                isInteractive: true,
                autoDismissAfter: nil
            )
        )

        XCTAssertEqual(session.notchState, .previewClosed)
        XCTAssertTrue(session.showsSneakPeekOverlay)
        XCTAssertEqual(session.currentSneakPeek?.kind, .attention)
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

        XCTAssertEqual(frame.width, 720, accuracy: 0.1)
        XCTAssertEqual(frame.height, 260, accuracy: 0.1)
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

    private func makeSettingsStore(activitySneakPreviewsHidden: Bool) -> SettingsStore {
        let suiteName = "ScreenSessionModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        store.activitySneakPreviewsHidden = activitySneakPreviewsHidden
        return store
    }
}
