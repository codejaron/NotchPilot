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
}
