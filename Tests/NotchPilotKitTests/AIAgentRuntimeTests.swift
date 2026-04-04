import XCTest
@testable import NotchPilotKit

final class AIAgentRuntimeTests: XCTestCase {
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
}
