import XCTest
@testable import NotchPilotKit

final class AIAgentRuntimeTests: XCTestCase {
    func testRealtimeApprovalResolutionRemovesPendingApproval() {
        let runtime = AIAgentRuntime()
        let approval = PendingApproval(
            requestID: "req-live",
            sessionID: "thr-live",
            host: .codex,
            approvalKind: .commandExecution,
            eventType: nil,
            payload: ApprovalPayload(
                title: "Command wants approval",
                toolName: "Command",
                previewText: "npm test",
                command: "npm test"
            ),
            capabilities: .none,
            availableActions: ApprovalAction.codexDefaultActions(for: .commandExecution),
            status: .pending
        )

        _ = runtime.apply(event: .approvalRequested(approval))
        XCTAssertEqual(runtime.pendingApprovals.map(\.requestID), ["req-live"])

        let effects = runtime.apply(event: .approvalResolved(requestID: "req-live"))

        XCTAssertEqual(effects, [.approvalDismissed(requestID: "req-live")])
        XCTAssertTrue(runtime.pendingApprovals.isEmpty)
    }

    func testNotificationEventsReturnImmediateEmptyResponse() {
        let runtime = AIAgentRuntime()
        let envelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-1",
            sessionID: "session-1",
            eventType: .postToolUse,
            capabilities: .none,
            needsResponse: false,
            payload: .generic([
                "tool_name": "Bash",
            ])
        )

        let result = runtime.handle(envelope: envelope)

        XCTAssertEqual(result, .respondNow(Data("{}".utf8)))
        XCTAssertEqual(runtime.sessions.map(\.id), ["session-1"])
    }

    func testDisconnectExpiresPendingApprovalAndRemovesIt() {
        let runtime = AIAgentRuntime()
        let envelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-2",
            sessionID: "session-2",
            eventType: .permissionRequest,
            capabilities: .persistentRules,
            needsResponse: true,
            payload: .permissionRequest(
                ApprovalPayload(
                    title: "Bash wants approval",
                    toolName: "Bash",
                    previewText: "rm -rf /tmp/demo"
                )
            )
        )

        let result = runtime.handle(envelope: envelope)
        XCTAssertEqual(result, .awaitDecision(requestID: "req-2"))
        XCTAssertEqual(runtime.pendingApprovals.map(\.requestID), ["req-2"])

        let expired = runtime.expirePendingApproval(requestID: "req-2")

        XCTAssertEqual(expired?.status, .expired)
        XCTAssertTrue(runtime.pendingApprovals.isEmpty)
    }

    func testPendingApprovalRetainsOriginalEventType() {
        let runtime = AIAgentRuntime()
        let envelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-4",
            sessionID: "session-4",
            eventType: .preToolUse,
            capabilities: .none,
            needsResponse: true,
            payload: .permissionRequest(
                ApprovalPayload(
                    title: "Bash wants approval",
                    toolName: "Bash",
                    previewText: "ls -la"
                )
            )
        )

        let result = runtime.handle(envelope: envelope)

        XCTAssertEqual(result, .awaitDecision(requestID: "req-4"))
        XCTAssertEqual(runtime.pendingApprovals.first?.eventType, .preToolUse)
    }

    func testUserPromptSubmitSetsSessionTitleAndPreservesTokensOnLaterPromptEvents() throws {
        let runtime = AIAgentRuntime()

        let usageEnvelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-5",
            sessionID: "session-5",
            eventType: .postToolUse,
            capabilities: .none,
            needsResponse: false,
            payload: .generic([
                "usage.input_tokens": "1200",
                "usage.output_tokens": "300",
            ])
        )

        let firstPromptEnvelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-6",
            sessionID: "session-5",
            eventType: .userPromptSubmit,
            capabilities: .none,
            needsResponse: false,
            payload: .generic([
                "prompt": "Build a backend server with express and sqlite",
            ])
        )

        let secondPromptEnvelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-7",
            sessionID: "session-5",
            eventType: .userPromptSubmit,
            capabilities: .none,
            needsResponse: false,
            payload: .generic([
                "prompt": "Overwrite me",
            ])
        )

        _ = runtime.handle(envelope: usageEnvelope)
        _ = runtime.handle(envelope: firstPromptEnvelope)
        _ = runtime.handle(envelope: secondPromptEnvelope)

        let session = try XCTUnwrap(runtime.sessions.first)
        XCTAssertEqual(session.sessionTitle, "Build a backend server with ex…")
        XCTAssertEqual(session.inputTokenCount, 1200)
        XCTAssertEqual(session.outputTokenCount, 300)
    }

    func testCodexSessionUpsertClearsTokenCountsWhenDesktopStreamOmitsThem() throws {
        let runtime = AIAgentRuntime()

        _ = runtime.apply(
            event: .sessionUpsert(
                AISession(
                    id: "codex-session",
                    host: .codex,
                    lastEventType: .sessionStart,
                    activityLabel: "Working",
                    inputTokenCount: 200,
                    outputTokenCount: 80
                )
            )
        )

        _ = runtime.apply(
            event: .sessionUpsert(
                AISession(
                    id: "codex-session",
                    host: .codex,
                    lastEventType: .sessionStart,
                    activityLabel: "Working",
                    inputTokenCount: nil,
                    outputTokenCount: nil
                )
            )
        )

        let session = try XCTUnwrap(runtime.sessions.first)
        XCTAssertNil(session.inputTokenCount)
        XCTAssertNil(session.outputTokenCount)
    }
}
