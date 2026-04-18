import AppKit
import SwiftUI
import XCTest
@testable import NotchPilotKit

final class AIPluginSupportTests: XCTestCase {
    private static let compactContext = NotchContext(
        screenID: "test-screen",
        notchState: .previewClosed,
        notchGeometry: NotchGeometry(
            compactSize: CGSize(width: 185, height: 32),
            expandedSize: CGSize(width: 520, height: 320)
        ),
        isPrimaryScreen: true
    )

    func testExpandedSessionListPresentationHidesEmptyAgentSurfaces() {
        let presentation = AIPluginExpandedSessionListPresentation(summaries: [])

        XCTAssertFalse(presentation.shouldRender)
    }

    @MainActor
    func testCompactMetricsPlaceRuntimeLeftAndTokensInRightColumnForAIHosts() throws {
        let runtimeWidth = measuredWidth(
            "2s",
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        )
        let inputTokenWidth = measuredWidth(
            "↑98.8K",
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
        let outputTokenWidth = measuredWidth(
            "↓1.3K",
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
        let expectedTokenColumnWidth = max(inputTokenWidth, outputTokenWidth)
        let previousHorizontalTokenWidth = inputTokenWidth + 6 + outputTokenWidth

        for host in [AIHost.claude, .codex] {
            let plugin = CompactMetricsProbePlugin(
                activity: AIPluginCompactActivity(
                    host: host,
                    label: "Working",
                    inputTokenCount: 98_765,
                    outputTokenCount: 1_300,
                    approvalCount: 0,
                    sessionTitle: nil,
                    runtimeDurationText: "2s"
                )
            )

            let metrics = try XCTUnwrap(plugin.compactMetrics(context: Self.compactContext))

            XCTAssertEqual(metrics.leftWidth, 22 + 5 + runtimeWidth, accuracy: 0.5)
            XCTAssertEqual(metrics.rightWidth, expectedTokenColumnWidth, accuracy: 0.5)
            XCTAssertLessThan(metrics.rightWidth, previousHorizontalTokenWidth)
            XCTAssertEqual(
                metrics.sideFrameWidth,
                max(34, metrics.leftWidth, metrics.rightWidth),
                accuracy: 0.5
            )
        }
    }

    @MainActor
    func testCompactViewRefreshesRuntimeWithoutPluginEvents() throws {
        let plugin = CompactRuntimeRefreshProbePlugin()
        let metrics = try XCTUnwrap(plugin.compactMetrics(context: Self.compactContext))
        let noticeLayout = AIPluginCompactApprovalNoticeLayout(
            notice: nil,
            baseTotalWidth: metrics.totalWidth
        )
        let view = AIPluginCompactView(
            plugin: plugin,
            context: Self.compactContext,
            approvalNotice: nil,
            noticeLayout: noticeLayout
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: noticeLayout.totalWidth, height: Self.compactContext.notchGeometry.compactSize.height)
        )

        hostingView.layoutSubtreeIfNeeded()
        let initialReadCount = plugin.activityReadCount

        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(plugin.activityReadCount, initialReadCount)
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

    func testExpandedSessionSummaryOnlyDimsCompletedSessions() {
        let working = AIPluginExpandedSessionSummary(
            id: "thread-working",
            host: .claude,
            title: "Working",
            subtitle: "Processing",
            phase: .working,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            inputTokenCount: nil,
            outputTokenCount: nil
        )
        let completed = AIPluginExpandedSessionSummary(
            id: "thread-completed",
            host: .claude,
            title: "Completed",
            subtitle: "Done",
            phase: .completed,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 1),
            inputTokenCount: nil,
            outputTokenCount: nil
        )

        XCTAssertFalse(working.isDimmed)
        XCTAssertTrue(completed.isDimmed)
    }

    func testSessionRowsOnlyUsePrimaryAreaForAttentionAndAlwaysExposeJumpTarget() {
        let attention = AIPluginExpandedSessionSummary(
            id: "thread-attention",
            host: .claude,
            title: "Needs approval",
            subtitle: "Bash",
            phase: .working,
            approvalCount: 1,
            approvalRequestID: "approval-1",
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            inputTokenCount: nil,
            outputTokenCount: nil
        )
        let ordinary = AIPluginExpandedSessionSummary(
            id: "thread-ordinary",
            host: .claude,
            title: "Working",
            subtitle: "Processing",
            phase: .working,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 1),
            inputTokenCount: nil,
            outputTokenCount: nil
        )

        XCTAssertEqual(attention.primaryRowAction, .reviewAttention)
        XCTAssertGreaterThanOrEqual(attention.jumpAccessoryHitWidth, 36)
        XCTAssertEqual(ordinary.primaryRowAction, .none)
        XCTAssertGreaterThanOrEqual(ordinary.jumpAccessoryHitWidth, 36)
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

    @MainActor
    func testClaudeApprovalSneakNoticePrefersDescriptionOverCommand() {
        let runtime = AIAgentRuntime()
        _ = runtime.handle(
            envelope: try! HookEventParser().parse(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "claude-approval-description",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "claude-session-description",
                      "tool_name": "Bash",
                      "tool_input": {
                        "command": "swift build 2>&1 | tail -30",
                        "description": "Build the Swift package"
                      }
                    }
                    """
                )
            )
        )

        let notice = AIPluginApprovalSneakNotice(
            pendingApprovals: runtime.pendingApprovals,
            codexSurface: nil
        )

        XCTAssertEqual(notice?.count, 1)
        XCTAssertEqual(notice?.text, "Build the Swift package")
    }

    func testCodexApprovalDetailPresentationShowsSummaryAboveCommandPreview() {
        let presentation = CodexApprovalDetailPresentation(
            surface: CodexActionableSurface(
                id: "surface-1",
                summary: "Do you want me to run the broader notch tests?",
                commandPreview: "/bin/zsh -lc 'swift test --filter \"NotchLayoutMetricsTests\"'",
                primaryButtonTitle: "Submit",
                cancelButtonTitle: "Skip"
            )
        )

        XCTAssertEqual(presentation.summaryText, "Do you want me to run the broader notch tests?")
        XCTAssertEqual(presentation.commandText, "/bin/zsh -lc 'swift test --filter \"NotchLayoutMetricsTests\"'")
    }

    func testStandaloneCodexTextInputPresentationPlacesIndexInsideField() {
        let presentation = CodexApprovalTextInputPresentation.standalone(
            textInput: CodexSurfaceTextInput(
                title: nil,
                text: "",
                isEditable: true
            ),
            index: 3
        )

        XCTAssertEqual(presentation.indexText, "3.")
        XCTAssertEqual(presentation.indexPlacement, .insideFieldLeading)
    }

    func testFeedbackCodexTextInputPresentationPlacesOptionIndexInsideField() {
        let presentation = CodexApprovalTextInputPresentation.feedback(
            textInput: CodexSurfaceTextInput(
                title: "Explain what to change",
                text: "",
                isEditable: true,
                attachedOptionID: "feedback"
            ),
            option: CodexSurfaceOption(
                id: "feedback",
                index: 3,
                title: "No, tell Codex how to adjust",
                isSelected: true
            )
        )

        XCTAssertEqual(presentation.indexText, "3.")
        XCTAssertEqual(presentation.indexPlacement, .insideFieldLeading)
        XCTAssertEqual(presentation.placeholder, "Explain what to change")
    }

    func testCompactApprovalNoticeLayoutUsesZeroHeightWithoutNotice() {
        let layout = AIPluginCompactApprovalNoticeLayout(
            notice: nil,
            baseTotalWidth: 280
        )

        XCTAssertEqual(layout.totalWidth, 280, accuracy: 0.1)
        XCTAssertEqual(layout.height, 0, accuracy: 0.1)
        XCTAssertEqual(layout.lineLimit, 1)
    }

    func testCompactApprovalNoticeLayoutCanGrowBeyondTwoLines() {
        let layout = AIPluginCompactApprovalNoticeLayout(
            notice: AIPluginApprovalSneakNotice(
                pendingApprovals: [],
                codexSurface: CodexActionableSurface(
                    id: "surface-long",
                    summary: String(
                        repeating: "Do you want me to run the broader notch verification command with the full approval preview visible? ",
                        count: 4
                    ),
                    commandPreview: "/bin/zsh -lc 'swift test'",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            ),
            baseTotalWidth: 280
        )

        XCTAssertGreaterThan(layout.totalWidth, 280)
        XCTAssertGreaterThan(layout.height, 44)
        XCTAssertNil(layout.lineLimit)
    }
}

@MainActor
private final class CompactMetricsProbePlugin: AIPluginRendering {
    let id = "compact-metrics-probe"
    let title = "Compact Metrics Probe"
    let iconSystemName = "sparkles"
    let accentColor: Color = .blue
    var isEnabled = true
    let dockOrder = 1
    let previewPriority: Int? = nil

    var sessions: [AISession] = []
    var pendingApprovals: [PendingApproval] = []
    var codexActionableSurface: CodexActionableSurface? = nil
    var currentCompactActivity: AIPluginCompactActivity?
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] = []
    var approvalSneakNotificationsEnabled = true

    init(activity: AIPluginCompactActivity) {
        self.currentCompactActivity = activity
    }

    func displayTitle(for session: AISession) -> String? { nil }

    func expandedSessionTitle(for session: AISession) -> String {
        hostDisplayName(for: session.host)
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}

@MainActor
private final class CompactRuntimeRefreshProbePlugin: AIPluginRendering {
    let id = "compact-runtime-refresh-probe"
    let title = "Compact Runtime Refresh Probe"
    let iconSystemName = "sparkles"
    let accentColor: Color = .blue
    var isEnabled = true
    let dockOrder = 1
    let previewPriority: Int? = nil

    var sessions: [AISession] = []
    var pendingApprovals: [PendingApproval] = []
    var codexActionableSurface: CodexActionableSurface? = nil
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] = []
    var approvalSneakNotificationsEnabled = true
    private(set) var activityReadCount = 0

    var currentCompactActivity: AIPluginCompactActivity? {
        activityReadCount += 1
        return AIPluginCompactActivity(
            host: .claude,
            label: "Working",
            inputTokenCount: 98_765,
            outputTokenCount: 1_300,
            approvalCount: 0,
            sessionTitle: nil,
            runtimeDurationText: "\(activityReadCount)s"
        )
    }

    func displayTitle(for session: AISession) -> String? { nil }

    func expandedSessionTitle(for session: AISession) -> String {
        hostDisplayName(for: session.host)
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}

private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
}
