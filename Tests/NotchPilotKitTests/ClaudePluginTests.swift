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

    @MainActor
    func testDisabledPluginIgnoresBridgeFramesAndDoesNotRenderInNotch() {
        let store = Self.makeSettingsStore()
        store.claudePluginEnabled = false
        let bus = EventBus()
        let plugin = ClaudePlugin(settingsStore: store)
        let recorder = SplitEventRecorder()
        let responseBox = SplitResponseBox()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-disabled",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-disabled-session",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo disabled" }
                }
                """
            ),
            respond: { data in
                responseBox.data = data
            }
        )

        XCTAssertFalse(plugin.isEnabled)
        XCTAssertTrue(plugin.pendingApprovals.isEmpty)
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertNil(plugin.preview(context: Self.previewContext))
        XCTAssertEqual(String(data: responseBox.data ?? Data(), encoding: .utf8), "{}")

        store.claudePluginEnabled = true
        XCTAssertTrue(plugin.isEnabled)

        bus.unsubscribe(token)
    }

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

    @MainActor
    func testPreToolUseDoesNotCreateApprovalOrSneakPeek() {
        let bus = EventBus()
        let plugin = ClaudePlugin()
        let recorder = SplitEventRecorder()
        let responseBox = SplitResponseBox()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-pretool-ls",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "claude-session-pretool",
                  "tool_name": "Bash",
                  "tool_input": { "command": "ls -la" }
                }
                """
            ),
            respond: { data in
                responseBox.data = data
            }
        )

        XCTAssertTrue(plugin.pendingApprovals.isEmpty)
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(String(data: responseBox.data ?? Data(), encoding: .utf8), "{}")

        bus.unsubscribe(token)
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

    @MainActor
    func testActivateSessionUsesStoredLaunchContext() {
        let focuser = RecordingAISessionFocuser()
        let plugin = ClaudePlugin(sessionFocuser: focuser)
        let bus = EventBus()

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-origin",
                origin: AISessionLaunchContext(
                    processIdentifier: 321,
                    bundleIdentifier: "com.apple.Terminal",
                    terminalIdentifier: "ttys021",
                    codexClientID: nil
                ),
                rawJSON: """
                {
                  "hook_event_name": "UserPromptSubmit",
                  "session_id": "claude-session-origin",
                  "prompt": "write a changelog"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(plugin.activateSession(id: "claude-session-origin"))
        XCTAssertEqual(focuser.focusedContexts.map(\.processIdentifier), [321])
        XCTAssertEqual(focuser.focusedContexts.map(\.terminalIdentifier), ["ttys021"])
    }

    func testVeryLongPermissionRequestPreviewCanGrowBeyondTwoLines() async {
        let plugin = await MainActor.run { ClaudePlugin() }
        let bus = await MainActor.run { EventBus() }
        let longCommand = String(
            repeating: "echo approval-preview-visibility-check ",
            count: 12
        )

        await MainActor.run {
            plugin.activate(bus: bus)
            plugin.handle(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "claude-long-preview",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "claude-session-long-preview",
                      "tool_name": "Bash",
                      "tool_input": { "command": "\(longCommand)" }
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let previewHeight = await MainActor.run {
            plugin.preview(context: Self.previewContext)?.height
        }

        XCTAssertGreaterThan(try XCTUnwrap(previewHeight), Self.previewContext.notchGeometry.compactSize.height + 44)
    }

    @MainActor
    func testDenyReturnsDenyAndClearsPendingApproval() {
        let plugin = ClaudePlugin()
        let responseBox = SplitResponseBox()

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-deny-feedback",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-deny-feedback",
                  "tool_name": "Bash",
                  "tool_input": { "command": "rm -rf /tmp/demo" }
                }
                """
            ),
            respond: { data in
                responseBox.data = data
            }
        )

        let action = try! XCTUnwrap(
            plugin.pendingApprovals.first?.availableActions.first(where: { $0.id == "claude-deny" })
        )

        plugin.respond(to: "claude-deny-feedback", with: action)

        let response = String(data: responseBox.data ?? Data(), encoding: .utf8)
        XCTAssertTrue(response?.contains(#""behavior":"deny""#) == true)
        XCTAssertTrue(plugin.pendingApprovals.isEmpty)
    }
}

private extension ClaudePluginTests {
    @MainActor
    static func makeSettingsStore() -> SettingsStore {
        let suiteName = "ClaudePluginTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(defaults: defaults)
    }
}

private final class RecordingAISessionFocuser: AISessionFocusing {
    private(set) var focusedContexts: [AISessionLaunchContext] = []
    private(set) var focusedCodexThreads: [String] = []

    func focus(context: AISessionLaunchContext, fallback: AISessionFocusFallback) -> Bool {
        focusedContexts.append(context)
        return true
    }

    func focusCodexThread(id: String, fallbackContext: AISessionLaunchContext?) -> Bool {
        focusedCodexThreads.append(id)
        return true
    }
}
