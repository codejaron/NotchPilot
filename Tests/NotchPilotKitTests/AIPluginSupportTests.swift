import XCTest
@testable import NotchPilotKit

final class AIPluginSupportTests: XCTestCase {
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

    func testApprovalDiffPreviewKeepsPlainContentNeutral() {
        let preview = AIPluginApprovalDiffPreview(content: """
        let value = 1
        print(value)
        """)

        XCTAssertFalse(preview.isSyntaxHighlighted)
        XCTAssertEqual(preview.lines.map(\.kind), [.context, .context])
        XCTAssertEqual(preview.lines.map(\.lineNumber), ["1", "2"])
        XCTAssertEqual(preview.lines.map(\.prefix), [" ", " "])
        XCTAssertEqual(preview.lines.map(\.text), ["let value = 1", "print(value)"])
    }

    func testApprovalDiffPreviewHighlightsUnifiedDiffContent() {
        let preview = AIPluginApprovalDiffPreview(content: """
        @@ -1,2 +1,2 @@
        -old line
         unchanged line
        +new line
        """)

        XCTAssertTrue(preview.isSyntaxHighlighted)
        XCTAssertEqual(preview.lines.map(\.kind), [.metadata, .removal, .context, .addition])
        XCTAssertEqual(preview.lines.map(\.lineNumber), ["", "1", "2", "2"])
        XCTAssertEqual(preview.lines.map(\.prefix), ["@", "-", " ", "+"])
        XCTAssertEqual(preview.lines.map(\.text), [
            "@@ -1,2 +1,2 @@",
            "old line",
            "unchanged line",
            "new line",
        ])
    }

    func testApprovalDiffPreviewBuildsLineDiffFromOriginalAndProposedContent() {
        let payload = ApprovalPayload(
            title: "Edit wants approval",
            toolName: "Edit",
            previewText: "/tmp/demo.txt",
            filePath: "/tmp/demo.txt",
            diffContent: "hello\nthere",
            originalContent: "hi\nthere"
        )

        let preview = AIPluginApprovalDiffPreview(payload: payload)

        XCTAssertTrue(preview.isSyntaxHighlighted)
        XCTAssertEqual(preview.lines.map(\.kind), [.removal, .addition, .context])
        XCTAssertEqual(preview.lines.map(\.lineNumber), ["1", "1", "2"])
        XCTAssertEqual(preview.lines.map(\.prefix), ["-", "+", " "])
        XCTAssertEqual(preview.lines.map(\.text), ["hi", "hello", "there"])
    }

    func testCodexApprovalSneakNoticePrefersSurfaceSummaryOverCommandPreview() {
        let notice = AIPluginApprovalSneakNotice(
            pendingApprovals: [],
            codexSurface: CodexActionableSurface(
                id: "surface-1",
                summary: "Run command?",
                commandPreview: "/bin/zsh -lc \"echo test\"",
                primaryButtonTitle: "Submit",
                cancelButtonTitle: "Skip"
            )
        )

        XCTAssertEqual(notice?.count, 1)
        XCTAssertEqual(notice?.text, "Run command?")
    }
}
