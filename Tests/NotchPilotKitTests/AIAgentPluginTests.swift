import AppKit
import SwiftUI
import XCTest
@testable import NotchPilotKit

private final class ResponseBox: @unchecked Sendable {
    var data: Data?
}

@MainActor
private final class EventRecorder {
    var events: [NotchEvent] = []
}

final class AIAgentPluginTests: XCTestCase {
    func testPermissionRequestEmitsInteractiveSneakPeek() async throws {
        let bus = await MainActor.run { EventBus() }
        let plugin = await MainActor.run { AIAgentPlugin() }
        let recorder = await MainActor.run { EventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }
        await MainActor.run {
            plugin.activate(bus: bus)
        }

        await MainActor.run {
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-1",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "session-1",
                      "tool_name": "Bash",
                      "tool_input": { "command": "rm -rf /tmp/demo" },
                      "capabilities": { "supports_persistent_rules": true }
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let receivedEvents = await MainActor.run { recorder.events }
        guard case let .sneakPeekRequested(request)? = receivedEvents.first else {
            return XCTFail("expected a sneak peek request")
        }

        XCTAssertEqual(request.pluginID, "ai")
        XCTAssertEqual(request.priority, 1000)
        XCTAssertEqual(request.target, .activeScreen)
        XCTAssertTrue(request.isInteractive)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testDisconnectExpiresApprovalAndDismissesPeek() async {
        let bus = await MainActor.run { EventBus() }
        let plugin = await MainActor.run { AIAgentPlugin() }
        let recorder = await MainActor.run { EventRecorder() }

        let token = await MainActor.run {
            bus.subscribe { event in
                recorder.events.append(event)
            }
        }
        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-2",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "session-2",
                      "tool_name": "Bash",
                      "tool_input": { "command": "rm -rf /tmp/demo" }
                    }
                    """
                ),
                respond: { _ in }
            )
            plugin.handleDisconnect(requestID: "req-2")
        }

        let receivedEvents = await MainActor.run { recorder.events }
        let dismissEvents = receivedEvents.compactMap { event -> UUID? in
            guard case let .dismissSneakPeek(requestID, _) = event else {
                return nil
            }
            return requestID
        }

        let pendingCount = await MainActor.run { plugin.pendingApprovals.count }
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(dismissEvents.count, 1)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testApprovingRequestReturnsEventSpecificResponse() async throws {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }
        let responseBox = ResponseBox()

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .codex,
                    requestID: "req-3",
                    rawJSON: """
                    {
                      "event": "PreToolUse",
                      "sessionId": "session-3",
                      "tool": {
                        "name": "shell",
                        "input": { "command": "ls -la" }
                      },
                      "capabilities": { "supportsPersistentRules": false }
                    }
                    """
                ),
                respond: { data in
                    responseBox.data = data
                }
            )
            plugin.respond(to: "req-3", with: .denyOnce)
        }

        XCTAssertEqual(
            String(data: try XCTUnwrap(responseBox.data), encoding: .utf8),
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied via NotchPilot"}}"#
        )
        let pendingCount = await MainActor.run { plugin.pendingApprovals.count }
        XCTAssertEqual(pendingCount, 0)
    }

    func testCurrentCompactActivityUsesMostRecentSessionAndFormatsTokens() async {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-live",
                    rawJSON: """
                    {
                      "hook_event_name": "PostToolUse",
                      "session_id": "session-live",
                      "phase": "thinking",
                      "usage": {
                        "input_tokens": 1234,
                        "output_tokens": 456
                      }
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        XCTAssertEqual(activity?.host, .claude)
        XCTAssertEqual(activity?.label, "Thinking")
        XCTAssertEqual(activity?.inputTokenCount, 1234)
        XCTAssertEqual(activity?.outputTokenCount, 456)
    }

    func testPendingApprovalOverridesCompactActivityHost() async {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-live-2",
                    rawJSON: """
                    {
                      "hook_event_name": "PostToolUse",
                      "session_id": "session-live-2",
                      "phase": "thinking"
                    }
                    """
                ),
                respond: { _ in }
            )
            plugin.handle(
                frame: BridgeFrame(
                    host: .codex,
                    requestID: "req-pending",
                    rawJSON: """
                    {
                      "event": "approval_request",
                      "sessionId": "session-pending",
                      "tool": {
                        "name": "shell",
                        "input": { "command": "ls -la" }
                      }
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        XCTAssertEqual(activity?.host, .codex)
        XCTAssertEqual(activity?.label, "Approval")
        XCTAssertEqual(activity?.approvalCount, 1)
    }

    func testCompactWidthReservesRealNotchGapForLiveActivity() async throws {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-gap",
                    rawJSON: """
                    {
                      "hook_event_name": "PostToolUse",
                      "session_id": "session-gap",
                      "phase": "thinking",
                      "usage": {
                        "input_tokens": 1000,
                        "output_tokens": 250
                      }
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let context = NotchContext(
            screenID: "primary",
            notchState: .closed,
            notchGeometry: NotchGeometry(
                compactSize: CGSize(width: 236, height: 38),
                expandedSize: CGSize(width: 520, height: 320)
            ),
            isPrimaryScreen: true
        )

        let compactWidth = await MainActor.run { plugin.compactWidth(context: context) }
        let resolvedWidth = try XCTUnwrap(compactWidth)
        let compactMetrics = await MainActor.run { plugin.compactMetrics(context: context) }
        let metrics = try XCTUnwrap(compactMetrics)
        XCTAssertEqual(metrics.sideFrameWidth, max(metrics.leftWidth, metrics.rightWidth), accuracy: 0.1)
        XCTAssertEqual(resolvedWidth, 236 + metrics.sideFrameWidth * 2 + 20, accuracy: 0.1)
        XCTAssertGreaterThan(resolvedWidth, 300)
    }

    func testExpandedSessionSummariesUseReadableFallbackInsteadOfSessionID() async {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-readable",
                    rawJSON: """
                    {
                      "hook_event_name": "SessionStart",
                      "session_id": "98ff2839-1111-2222-3333-444444444444"
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let summaries = await MainActor.run { plugin.expandedSessionSummaries }
        XCTAssertEqual(summaries.first?.title, "Claude Code")
        XCTAssertEqual(summaries.first?.subtitle, "Connected")
    }

    func testExpandedSessionSummariesSortPendingApprovalFirst() async {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-processing",
                    rawJSON: """
                    {
                      "hook_event_name": "UserPromptSubmit",
                      "session_id": "session-processing",
                      "prompt": "Build a backend server with express"
                    }
                    """
                ),
                respond: { _ in }
            )
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-processing-2",
                    rawJSON: """
                    {
                      "hook_event_name": "PostToolUse",
                      "session_id": "session-processing",
                      "phase": "processing"
                    }
                    """
                ),
                respond: { _ in }
            )
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-pending-title",
                    rawJSON: """
                    {
                      "hook_event_name": "UserPromptSubmit",
                      "session_id": "session-pending",
                      "prompt": "create a react dashboard"
                    }
                    """
                ),
                respond: { _ in }
            )
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "req-pending-approval",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "session-pending",
                      "tool_name": "Bash",
                      "tool_input": { "command": "npm create vite@latest" }
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let summaries = await MainActor.run { plugin.expandedSessionSummaries }
        XCTAssertEqual(summaries.map(\.title), [
            "create a react dashboard",
            "Build a backend server with ex…",
        ])
        XCTAssertEqual(summaries.first?.subtitle, "Bash")
        XCTAssertEqual(summaries.first?.approvalCount, 1)
        XCTAssertEqual(summaries.first?.approvalRequestID, "req-pending-approval")
        XCTAssertNil(summaries.last?.approvalRequestID)
    }

    func testApprovalReviewStateAdvancesToNextPendingApprovalWhileReviewing() {
        var state = AIApprovalReviewState()
        state.beginReviewing(requestID: "req-queue-1")

        state.syncPendingRequestIDs(["req-queue-2"])

        XCTAssertTrue(state.isReviewingApprovals)
        XCTAssertEqual(state.selectedApprovalRequestID, "req-queue-2")
    }

    func testApprovalReviewStateStaysExitedAfterManualBackUntilUserReenters() {
        var state = AIApprovalReviewState()
        state.beginReviewing(requestID: "req-queue-1")
        state.exitReviewing()

        state.syncPendingRequestIDs(["req-queue-2"])

        XCTAssertFalse(state.isReviewingApprovals)
        XCTAssertNil(state.selectedApprovalRequestID)
    }

    func testApprovalReviewStateStopsReviewingWhenQueueIsEmpty() {
        var state = AIApprovalReviewState()
        state.beginReviewing(requestID: "req-queue-1")

        state.syncPendingRequestIDs([])

        XCTAssertFalse(state.isReviewingApprovals)
        XCTAssertNil(state.selectedApprovalRequestID)
    }

    func testApprovalDiffPreviewKeepsPlainContentNeutral() {
        let preview = ApprovalDiffPreview(content: """
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
        let preview = ApprovalDiffPreview(content: """
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

        let preview = ApprovalDiffPreview(payload: payload)

        XCTAssertTrue(preview.isSyntaxHighlighted)
        XCTAssertEqual(preview.lines.map(\.kind), [.removal, .addition, .context])
        XCTAssertEqual(preview.lines.map(\.lineNumber), ["1", "1", "2"])
        XCTAssertEqual(preview.lines.map(\.prefix), ["-", "+", " "])
        XCTAssertEqual(preview.lines.map(\.text), ["hi", "hello", "there"])
    }

    func testExpandedViewRendersInsideVerticalScrollView() async throws {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
        }

        let scrollViewCount = try await MainActor.run {
            let harness = ExpandedViewHarness(
                rootView: plugin.expandedView(
                    context: NotchContext(
                        screenID: "primary",
                        notchState: .open,
                        notchGeometry: NotchGeometry(
                            compactSize: CGSize(width: 236, height: 38),
                            expandedSize: CGSize(width: 520, height: 320)
                        ),
                        isPrimaryScreen: true
                    )
                )
            )
            return harness.scrollViewCount()
        }

        XCTAssertGreaterThan(scrollViewCount, 0)
    }
}

@MainActor
private struct ExpandedViewHarness {
    let window: NSWindow
    let hostingController: NSHostingController<AnyView>

    init(rootView: AnyView) {
        _ = NSApplication.shared
        hostingController = NSHostingController(rootView: rootView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        pump()
    }

    func scrollViewCount() -> Int {
        collectSubviews(ofType: NSScrollView.self, in: hostingController.view).count
    }

    private func pump() {
        hostingController.loadView()
        hostingController.view.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 520, height: 320)
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingController.view.layoutSubtreeIfNeeded()
    }

    private func collectSubviews<ViewType: NSView>(ofType type: ViewType.Type, in root: NSView) -> [ViewType] {
        var matches: [ViewType] = []
        if let root = root as? ViewType {
            matches.append(root)
        }

        for subview in root.subviews {
            matches.append(contentsOf: collectSubviews(ofType: type, in: subview))
        }

        return matches
    }
}
