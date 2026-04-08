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

private final class FakeCodexContextMonitor: @unchecked Sendable, CodexDesktopContextMonitoring {
    var onThreadContextChanged: (@Sendable (CodexThreadUpdate) -> Void)?
    var onConnectionStateChanged: (@Sendable (CodexDesktopConnectionState) -> Void)?

    func start() {}
    func stop() {}

    func emit(update: CodexThreadUpdate) {
        onThreadContextChanged?(update)
    }

    func emit(
        context: CodexThreadContext,
        marksActivity: Bool = true
    ) {
        onThreadContextChanged?(CodexThreadUpdate(context: context, marksActivity: marksActivity))
    }

    func emit(connection: CodexDesktopConnectionState) {
        onConnectionStateChanged?(connection)
    }
}

private final class FakeCodexAXMonitor: @unchecked Sendable, CodexDesktopAXMonitoring {
    var onPermissionStateChanged: (@Sendable (CodexDesktopAXPermissionState) -> Void)?
    var onSurfaceChanged: (@Sendable (CodexActionableSurface?) -> Void)?
    private(set) var performedActions: [(CodexSurfaceAction, String)] = []
    private(set) var selectedOptions: [(String, String)] = []
    private(set) var updatedTexts: [(String, String)] = []

    func start() {}
    func stop() {}

    @discardableResult
    func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool {
        performedActions.append((action, surfaceID))
        return true
    }

    @discardableResult
    func selectOption(_ optionID: String, on surfaceID: String) -> Bool {
        selectedOptions.append((optionID, surfaceID))
        return true
    }

    @discardableResult
    func updateText(_ text: String, on surfaceID: String) -> Bool {
        updatedTexts.append((text, surfaceID))
        return true
    }

    func emit(permission: CodexDesktopAXPermissionState) {
        onPermissionStateChanged?(permission)
    }

    func emit(surface: CodexActionableSurface?) {
        onSurfaceChanged?(surface)
    }
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
                    host: .claude,
                    requestID: "req-3",
                    rawJSON: """
                    {
                      "hook_event_name": "PreToolUse",
                      "session_id": "session-3",
                      "tool_name": "Bash",
                      "tool_input": { "command": "ls -la" }
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

    func testCodexHookFramesAreIgnored() async {
        let plugin = await MainActor.run { AIAgentPlugin() }
        let bus = await MainActor.run { EventBus() }
        let responseBox = ResponseBox()

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
                    host: .claude,
                    requestID: "req-pending",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "session-pending",
                      "tool_name": "Bash",
                      "tool_input": { "command": "ls -la" }
                    }
                    """
                ),
                respond: { _ in }
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        XCTAssertEqual(activity?.host, .claude)
        XCTAssertEqual(activity?.label, "Approval")
        XCTAssertEqual(activity?.approvalCount, 1)
    }

    func testCodexActionableSurfaceDrivesCompactActivityAndSessionSummary() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-1",
                    title: "Write plan",
                    activityLabel: "Plan",
                    phase: .plan,
                    inputTokenCount: 120,
                    outputTokenCount: 45
                )
            )
            codexAXMonitor.emit(permission: .granted)
            codexAXMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-1",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        let summaries = await MainActor.run { plugin.expandedSessionSummaries }

        XCTAssertEqual(activity?.host, .codex)
        XCTAssertEqual(activity?.label, "Action Needed")
        XCTAssertEqual(activity?.approvalCount, 1)
        XCTAssertEqual(activity?.sessionTitle, "Write plan")
        XCTAssertEqual(summaries.first?.codexSurfaceID, "surface-1")
        XCTAssertEqual(summaries.first?.subtitle, "Action Needed")
    }

    func testCodexSurfaceWithoutThreadIDUsesCurrentActiveIPCThreadContext() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let now = Date(timeIntervalSince1970: 3)
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor,
                nowProvider: { now }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-active",
                    title: "Current Active Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 1)
                ),
                marksActivity: true
            )
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-metadata-only",
                    title: "Metadata Only Thread",
                    activityLabel: "Connected",
                    phase: .connected,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
                marksActivity: false
            )
            codexAXMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-nil-thread",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        await Task.yield()

        let title = await MainActor.run {
            plugin.preferredCodexTitle(for: plugin.codexActionableSurface)
        }

        XCTAssertEqual(title, "Current Active Thread")
    }

    func testCodexSurfaceWithoutActiveSessionUsesLatestIPCContextTitleForDisplay() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let now = Date(timeIntervalSince1970: 3)
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor,
                nowProvider: { now }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-metadata-current",
                    title: "IPC Current Thread",
                    activityLabel: "Connected",
                    phase: .connected,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
                marksActivity: false
            )
            codexAXMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-metadata-current",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        let title = await MainActor.run {
            plugin.preferredCodexTitle(for: plugin.codexActionableSurface)
        }

        XCTAssertEqual(title, "IPC Current Thread")
    }

    func testCodexSessionTitleRefreshesWhenIPCMetadataArrivesAfterActivity() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let now = Date(timeIntervalSince1970: 3)
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor,
                nowProvider: { now }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-title",
                    title: nil,
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 1)
                ),
                marksActivity: true
            )
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-thread-title",
                    title: "Real IPC Thread Title",
                    activityLabel: "Completed",
                    phase: .completed,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
                marksActivity: false
            )
        }

        let summaries = await MainActor.run { plugin.expandedSessionSummaries }

        XCTAssertEqual(summaries.first?.id, "codex-thread-title")
        XCTAssertEqual(summaries.first?.title, "Real IPC Thread Title")
    }

    func testCodexSurfaceWithoutThreadIDBindsOnlyToCurrentActiveCodexSession() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let now = Date(timeIntervalSince1970: 3)
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor,
                nowProvider: { now }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-older",
                    title: "Older Thread",
                    activityLabel: "Completed",
                    phase: .completed,
                    updatedAt: Date(timeIntervalSince1970: 1)
                ),
                marksActivity: true
            )
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-current",
                    title: "Current Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
                marksActivity: true
            )
            codexAXMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-current",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        await Task.yield()

        let summaries = await MainActor.run { plugin.expandedSessionSummaries }
        let attentionRows = summaries.filter(\.hasAttention)

        XCTAssertEqual(attentionRows.map(\.id), ["codex-current"])
        XCTAssertEqual(attentionRows.map(\.title), ["Current Thread"])
    }

    func testPerformingCodexPrimaryActionClearsSurfaceImmediately() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexAXMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-open",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
        }

        await Task.yield()

        await MainActor.run {
            _ = plugin.performCodexAction(.primary, surfaceID: "surface-open")
        }

        let performedActions = codexAXMonitor.performedActions
        let surface = await MainActor.run { plugin.codexActionableSurface }

        XCTAssertEqual(performedActions.map(\.0), [.primary])
        XCTAssertEqual(performedActions.map(\.1), ["surface-open"])
        XCTAssertNil(surface)
    }

    func testNilCodexSurfaceImmediatelyClearsCurrentSurface() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexAXMonitor.emit(
                surface: CodexActionableSurface(
                    id: "surface-stable",
                    summary: "Run command?",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            )
            codexAXMonitor.emit(surface: nil)
        }

        let surface = await MainActor.run { plugin.codexActionableSurface }
        XCTAssertNil(surface)
    }

    func testSelectingCodexOptionUpdatesCurrentSurfaceImmediately() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor
            )
        }

        let surface = CodexActionableSurface(
            id: "surface-options",
            summary: "Run command?",
            primaryButtonTitle: "提交",
            cancelButtonTitle: "跳过",
            options: [
                CodexSurfaceOption(id: "option-1", index: 1, title: "是", isSelected: true),
                CodexSurfaceOption(id: "option-2", index: 2, title: "总是允许", isSelected: false),
                CodexSurfaceOption(id: "option-3", index: 3, title: "否，请告知 Codex 如何调整", isSelected: false),
            ],
            textInput: CodexSurfaceTextInput(text: "", isEditable: true)
        )

        await MainActor.run {
            plugin.activate(bus: bus)
            codexAXMonitor.emit(surface: surface)
        }

        await Task.yield()

        await MainActor.run {
            _ = plugin.selectCodexOption("option-3", surfaceID: "surface-options")
        }

        let selectedOptions = codexAXMonitor.selectedOptions
        let updatedSurface = await MainActor.run { plugin.codexActionableSurface }

        XCTAssertEqual(selectedOptions.map(\.0), ["option-3"])
        XCTAssertEqual(selectedOptions.map(\.1), ["surface-options"])
        XCTAssertEqual(
            updatedSurface?.options.map(\.isSelected),
            [false, false, true]
        )
    }

    func testUpdatingCodexTextUpdatesCurrentSurfaceImmediately() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor
            )
        }

        let surface = CodexActionableSurface(
            id: "surface-text",
            summary: "Run command?",
            primaryButtonTitle: "提交",
            cancelButtonTitle: "跳过",
            options: [
                CodexSurfaceOption(id: "option-1", index: 1, title: "是", isSelected: false),
                CodexSurfaceOption(id: "option-2", index: 2, title: "总是允许", isSelected: false),
                CodexSurfaceOption(id: "option-3", index: 3, title: "否，请告知 Codex 如何调整", isSelected: true),
            ],
            textInput: CodexSurfaceTextInput(text: "", isEditable: true)
        )

        await MainActor.run {
            plugin.activate(bus: bus)
            codexAXMonitor.emit(surface: surface)
        }

        await Task.yield()

        await MainActor.run {
            _ = plugin.updateCodexText("请改用 mv", surfaceID: "surface-text")
        }

        let updatedTexts = codexAXMonitor.updatedTexts
        let updatedSurface = await MainActor.run { plugin.codexActionableSurface }

        XCTAssertEqual(updatedTexts.map(\.0), ["请改用 mv"])
        XCTAssertEqual(updatedTexts.map(\.1), ["surface-text"])
        XCTAssertEqual(updatedSurface?.textInput?.text, "请改用 mv")
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

        let scrollViewCount = await MainActor.run {
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

    func testSnapshotOnlyCodexThreadDoesNotAppearInActivityOrSummaries() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-snapshot-only",
                    title: "Old Snapshot",
                    activityLabel: "Completed",
                    phase: .completed
                ),
                marksActivity: false
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        let summaries = await MainActor.run { plugin.expandedSessionSummaries }

        XCTAssertNil(activity)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testStaleCodexActivityOlderThan24HoursIsFilteredOut() async {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor,
                nowProvider: { now }
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-stale",
                    title: "Stale Thread",
                    activityLabel: "Completed",
                    phase: .completed,
                    updatedAt: now.addingTimeInterval(-(25 * 60 * 60))
                )
            )
        }

        let activity = await MainActor.run { plugin.currentCompactActivity }
        let summaries = await MainActor.run { plugin.expandedSessionSummaries }

        XCTAssertNil(activity)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testDeactivateClearsCodexActivityStateUntilNewLiveUpdateArrives() async {
        let bus = await MainActor.run { EventBus() }
        let codexMonitor = FakeCodexContextMonitor()
        let codexAXMonitor = FakeCodexAXMonitor()
        let plugin = await MainActor.run {
            AIAgentPlugin(
                codexMonitor: codexMonitor,
                codexAXMonitor: codexAXMonitor
            )
        }

        await MainActor.run {
            plugin.activate(bus: bus)
            codexMonitor.emit(
                context: CodexThreadContext(
                    threadID: "codex-live",
                    title: "Live Thread",
                    activityLabel: "Working",
                    phase: .working
                )
            )
        }

        let beforeDeactivate = await MainActor.run { plugin.expandedSessionSummaries }
        XCTAssertEqual(beforeDeactivate.map(\.title), ["Live Thread"])

        await MainActor.run {
            plugin.deactivate()
            plugin.activate(bus: bus)
        }

        let afterReactivate = await MainActor.run { plugin.expandedSessionSummaries }
        XCTAssertTrue(afterReactivate.isEmpty)
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
