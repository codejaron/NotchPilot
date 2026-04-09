import XCTest
@testable import NotchPilotKit

final class ClaudePluginTests: XCTestCase {
    func testPermissionRequestEmitsInteractiveSneakPeek() async {
        let bus = await MainActor.run { EventBus() }
        let plugin = await MainActor.run { ClaudePlugin() }
        let recorder = await MainActor.run { SplitEventRecorder() }

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
                    requestID: "claude-req-1",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "claude-session-1",
                      "tool_name": "Bash",
                      "tool_input": { "command": "rm -rf /tmp/demo" }
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

        XCTAssertEqual(request.pluginID, "claude")
        XCTAssertEqual(request.priority, 1000)
        XCTAssertTrue(request.isInteractive)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    func testCodexHookFramesAreIgnored() async {
        let plugin = await MainActor.run { ClaudePlugin() }
        let bus = await MainActor.run { EventBus() }
        let responseBox = SplitResponseBox()

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .codex,
                    requestID: "stale-codex-hook",
                    rawJSON: """
                    {
                      "event": "stale_codex_hook",
                      "sessionId": "codex-session"
                    }
                    """
                ),
                respond: { data in
                    responseBox.data = data
                }
            )
        }

        let pendingCount = await MainActor.run { plugin.pendingApprovals.count }
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(String(data: responseBox.data ?? Data(), encoding: .utf8), "{}")
    }
}
