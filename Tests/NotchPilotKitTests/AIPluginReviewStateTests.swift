import XCTest
@testable import NotchPilotKit

final class AIPluginReviewStateTests: XCTestCase {
    func testExpandedSessionListPresentationHidesEmptyAgentSurfaces() {
        let presentation = AIPluginExpandedSessionListPresentation(summaries: [])

        XCTAssertFalse(presentation.shouldRender)
    }

    func testExpandedSessionListPresentationRendersWhenAThreadExists() {
        let summary = AIPluginExpandedSessionSummary(
            id: "thread-1",
            host: .claude,
            title: "create a react dashboard for my app",
            subtitle: "Processing",
            phase: .working,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            inputTokenCount: nil,
            outputTokenCount: nil
        )

        let presentation = AIPluginExpandedSessionListPresentation(summaries: [summary])

        XCTAssertTrue(presentation.shouldRender)
    }

    func testApprovalReviewStateAdvancesToNextPendingApprovalWhileReviewing() {
        var state = AIPluginApprovalReviewState()
        state.beginReviewing(requestID: "req-queue-1")

        state.syncPendingRequestIDs(["req-queue-2"])

        XCTAssertTrue(state.isReviewingApprovals)
        XCTAssertEqual(state.selectedApprovalRequestID, "req-queue-2")
    }

    func testApprovalReviewStateStaysExitedAfterManualBackUntilUserReenters() {
        var state = AIPluginApprovalReviewState()
        state.beginReviewing(requestID: "req-queue-1")
        state.exitReviewing()

        state.syncPendingRequestIDs(["req-queue-2"])

        XCTAssertFalse(state.isReviewingApprovals)
        XCTAssertNil(state.selectedApprovalRequestID)
    }

    func testApprovalReviewStateStopsReviewingWhenQueueIsEmpty() {
        var state = AIPluginApprovalReviewState()
        state.beginReviewing(requestID: "req-queue-1")

        state.syncPendingRequestIDs([])

        XCTAssertFalse(state.isReviewingApprovals)
        XCTAssertNil(state.selectedApprovalRequestID)
    }

    func testCodexSurfaceReviewStateDoesNotAutoSelectInitialSurface() {
        var state = AIPluginCodexSurfaceReviewState()

        state.sync(
            currentSurfaceID: "surface-initial",
            isReviewingApprovals: false,
            currentSelectionMatchesSurface: false
        )

        XCTAssertNil(state.selectedSurfaceID)
    }

    func testCodexSurfaceReviewStateDoesNotStealFocusWhileReviewingApprovals() {
        var state = AIPluginCodexSurfaceReviewState()

        state.sync(
            currentSurfaceID: "surface-ignored",
            isReviewingApprovals: true,
            currentSelectionMatchesSurface: false
        )

        XCTAssertNil(state.selectedSurfaceID)
    }

    func testCodexSurfaceReviewStateRetargetsWhenPreviousSurfaceBecomesStale() {
        var state = AIPluginCodexSurfaceReviewState(selectedSurfaceID: "surface-old")

        state.sync(
            currentSurfaceID: "surface-new",
            isReviewingApprovals: false,
            currentSelectionMatchesSurface: false
        )

        XCTAssertEqual(state.selectedSurfaceID, "surface-new")
    }
}
