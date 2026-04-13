import XCTest
@testable import NotchPilotKit

final class ClaudePluginTests: XCTestCase {
    private static let previewContext = NotchContext(
        screenID: "test-screen",
        notchState: .previewClosed,
        notchGeometry: NotchGeometry(
            compactSize: CGSize(width: 185, height: 32),
            expandedSize: CGSize(width: 520, height: 320)
        ),
        isPrimaryScreen: true
    )

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

    @MainActor
    func testPermissionRequestDoesNotEmitSneakPeekWhenApprovalSneakSettingIsDisabled() {
        let previousValue = SettingsStore.shared.approvalSneakNotificationsEnabled
        SettingsStore.shared.approvalSneakNotificationsEnabled = false
        defer {
            SettingsStore.shared.approvalSneakNotificationsEnabled = previousValue
        }

        let bus = EventBus()
        let plugin = ClaudePlugin()
        let recorder = SplitEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-req-disabled",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-disabled",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo hidden" }
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertNil(plugin.preview(context: Self.previewContext))

        bus.unsubscribe(token)
    }

    @MainActor
    func testReenablingApprovalSneakPresentsExistingPendingApproval() {
        let previousValue = SettingsStore.shared.approvalSneakNotificationsEnabled
        SettingsStore.shared.approvalSneakNotificationsEnabled = false
        defer {
            SettingsStore.shared.approvalSneakNotificationsEnabled = previousValue
        }

        let bus = EventBus()
        let plugin = ClaudePlugin()
        let recorder = SplitEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-req-reenable",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-reenable",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo reenable" }
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(recorder.events.isEmpty)

        SettingsStore.shared.approvalSneakNotificationsEnabled = true

        guard case let .sneakPeekRequested(request)? = recorder.events.first else {
            XCTFail("Expected sneak peek request after reenabling approval sneak")
            bus.unsubscribe(token)
            return
        }

        XCTAssertEqual(request.pluginID, "claude")
        XCTAssertTrue(request.isInteractive)
        XCTAssertNotNil(plugin.preview(context: Self.previewContext))

        bus.unsubscribe(token)
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

    func testStoppedSessionDoesNotRenderCompactPreviewWithoutApproval() async {
        let plugin = await MainActor.run { ClaudePlugin() }
        let bus = await MainActor.run { EventBus() }

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "claude-stop-1",
                    rawJSON: """
                    {
                      "hook_event_name": "Stop",
                      "session_id": "claude-session-stop-1"
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let hasPreview = await MainActor.run {
            plugin.preview(context: Self.previewContext) != nil
        }

        XCTAssertFalse(hasPreview)
    }
}
