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
            availableActions: [],
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
            launchContext: AISessionLaunchContext(
                processIdentifier: 100,
                bundleIdentifier: "com.apple.Terminal",
                terminalIdentifier: "ttys010",
                codexClientID: nil
            ),
            payload: .generic([
                "tool_name": "Bash",
            ])
        )

        let result = runtime.handle(envelope: envelope)

        XCTAssertEqual(result, .respondNow(Data("{}".utf8)))
        XCTAssertEqual(runtime.sessions.map(\.id), ["session-1"])
        XCTAssertEqual(runtime.sessions.first?.launchContext?.bundleIdentifier, "com.apple.Terminal")
    }

    func testSessionLaunchContextPreservesWhereSessionStarted() {
        let runtime = AIAgentRuntime()
        let firstEnvelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-first",
            sessionID: "session-origin",
            eventType: .sessionStart,
            capabilities: .none,
            needsResponse: false,
            launchContext: AISessionLaunchContext(
                processIdentifier: 100,
                bundleIdentifier: "com.apple.Terminal",
                terminalIdentifier: "ttys010",
                codexClientID: nil
            ),
            payload: .generic([:])
        )
        let laterEnvelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-later",
            sessionID: "session-origin",
            eventType: .postToolUse,
            capabilities: .none,
            needsResponse: false,
            launchContext: AISessionLaunchContext(
                processIdentifier: 200,
                bundleIdentifier: "com.anthropic.claudefordesktop",
                terminalIdentifier: nil,
                codexClientID: nil
            ),
            payload: .generic(["tool_name": "Bash"])
        )

        _ = runtime.handle(envelope: firstEnvelope)
        _ = runtime.handle(envelope: laterEnvelope)

        XCTAssertEqual(runtime.sessions.first?.launchContext?.processIdentifier, 100)
        XCTAssertEqual(runtime.sessions.first?.launchContext?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(runtime.sessions.first?.launchContext?.terminalIdentifier, "ttys010")
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

    func testUserPromptSubmitSetsSessionTitleAndPreservesTokensFromTranscriptReader() throws {
        let runtime = AIAgentRuntime()

        let bootstrapEnvelope = AIBridgeEnvelope(
            host: .claude,
            requestID: "req-5",
            sessionID: "session-5",
            eventType: .postToolUse,
            capabilities: .none,
            needsResponse: false,
            payload: .generic([:])
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

        _ = runtime.handle(envelope: bootstrapEnvelope)
        // Tokens come from the transcript reader (post-tool-use hooks never carry usage).
        XCTAssertTrue(runtime.updateTokenCounts(
            sessionID: "session-5",
            inputTokenCount: 1200,
            outputTokenCount: 300
        ))
        _ = runtime.handle(envelope: firstPromptEnvelope)
        _ = runtime.handle(envelope: secondPromptEnvelope)

        let session = try XCTUnwrap(runtime.sessions.first)
        XCTAssertEqual(session.sessionTitle, "Build a backend server with ex…")
        XCTAssertEqual(session.inputTokenCount, 1200)
        XCTAssertEqual(session.outputTokenCount, 300)
    }

    func testUpdateTokenCountsReturnsFalseForUnknownSession() {
        let runtime = AIAgentRuntime()

        let updated = runtime.updateTokenCounts(
            sessionID: "missing",
            inputTokenCount: 1,
            outputTokenCount: 2
        )

        XCTAssertFalse(updated)
    }

    func testUpdateTokenCountsReturnsFalseWhenValuesUnchanged() {
        let runtime = AIAgentRuntime()
        _ = runtime.handle(envelope: AIBridgeEnvelope(
            host: .claude,
            requestID: "req-tok",
            sessionID: "session-tok",
            eventType: .postToolUse,
            capabilities: .none,
            needsResponse: false,
            payload: .generic([:])
        ))

        XCTAssertTrue(runtime.updateTokenCounts(
            sessionID: "session-tok",
            inputTokenCount: 100,
            outputTokenCount: 50
        ))
        XCTAssertFalse(runtime.updateTokenCounts(
            sessionID: "session-tok",
            inputTokenCount: 100,
            outputTokenCount: 50
        ))
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
