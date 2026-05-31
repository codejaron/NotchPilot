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
        // The plugin's aggregate `isEnabled` is `claudeEnabled || devinEnabled`,
        // so both flags must be off to disable the plugin end-to-end.
        store.claudePluginEnabled = false
        store.devinPluginEnabled = false
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

    /// When the user disables only the Claude toggle but keeps Devin on, the
    /// plugin must keep processing Devin frames while silently dropping Claude
    /// ones. This is the headline feature of the per-host enable split.
    @MainActor
    func testDevinFrameIsProcessedEvenWhenClaudeToggleIsOff() {
        let store = Self.makeSettingsStore()
        store.claudePluginEnabled = false
        store.devinPluginEnabled = true
        let bus = EventBus()
        let plugin = ClaudePlugin(settingsStore: store)
        let claudeResponse = SplitResponseBox()
        let devinResponse = SplitResponseBox()

        plugin.activate(bus: bus)

        // Aggregate isEnabled is true because Devin is on.
        XCTAssertTrue(plugin.isEnabled)

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-blocked",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "claude-session",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo hi" }
                }
                """
            ),
            respond: { data in claudeResponse.data = data }
        )

        plugin.handle(
            frame: BridgeFrame(
                host: .devin,
                requestID: "devin-allowed",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "notchpilot-agent-pid-30716",
                  "tool_name": "exec",
                  "tool_input": { "command": "ls" }
                }
                """
            ),
            respond: { data in devinResponse.data = data }
        )

        // Claude frame must be dropped (empty JSON, no session created)…
        XCTAssertEqual(String(data: claudeResponse.data ?? Data(), encoding: .utf8), "{}")
        XCTAssertFalse(plugin.sessions.contains { $0.host == .claude })
        // …while the Devin frame must surface as a tracked session.
        XCTAssertTrue(plugin.sessions.contains { $0.host == .devin && $0.id == "notchpilot-agent-pid-30716" })
    }

    /// The reverse case — Devin off, Claude on — also has to keep Claude
    /// flowing. This is the existing-user upgrade path.
    @MainActor
    func testClaudeFrameIsProcessedEvenWhenDevinToggleIsOff() {
        let store = Self.makeSettingsStore()
        store.claudePluginEnabled = true
        store.devinPluginEnabled = false
        let bus = EventBus()
        let plugin = ClaudePlugin(settingsStore: store)
        let claudeResponse = SplitResponseBox()
        let devinResponse = SplitResponseBox()

        plugin.activate(bus: bus)
        XCTAssertTrue(plugin.isEnabled)

        plugin.handle(
            frame: BridgeFrame(
                host: .devin,
                requestID: "devin-blocked",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "notchpilot-agent-pid-99",
                  "tool_name": "exec",
                  "tool_input": { "command": "pwd" }
                }
                """
            ),
            respond: { data in devinResponse.data = data }
        )

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-allowed",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "claude-session",
                  "tool_name": "Bash",
                  "tool_input": { "command": "ls" }
                }
                """
            ),
            respond: { data in claudeResponse.data = data }
        )

        XCTAssertEqual(String(data: devinResponse.data ?? Data(), encoding: .utf8), "{}")
        XCTAssertFalse(plugin.sessions.contains { $0.host == .devin })
        XCTAssertTrue(plugin.sessions.contains { $0.host == .claude && $0.id == "claude-session" })
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
            Self.sendPreToolUse(
                plugin: plugin,
                requestID: "claude-pre-req-1",
                sessionID: "claude-session-1",
                command: "rm -rf /tmp/demo",
                toolUseID: "toolu_req_1"
            )
            recorder.events.removeAll()
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
        let attentionRequest = receivedEvents.compactMap { event -> SneakPeekRequest? in
            guard case let .sneakPeekRequested(request) = event, request.kind == .attention else {
                return nil
            }
            return request
        }.first
        guard let request = attentionRequest else {
            return XCTFail("expected a sneak peek request")
        }

        XCTAssertEqual(request.pluginID, "claude")
        XCTAssertEqual(request.priority, SneakPeekRequestPriority.aiApproval)
        XCTAssertLessThan(request.priority, SneakPeekRequestPriority.mediaPlayback)
        XCTAssertEqual(request.kind, .attention)
        XCTAssertTrue(request.isInteractive)

        let activity = await MainActor.run { plugin.currentCompactActivity }
        XCTAssertEqual(activity?.host, .claude)
        XCTAssertEqual(activity?.label, "Action Needed")
        XCTAssertEqual(activity?.approvalCount, 0)

        await MainActor.run {
            bus.unsubscribe(token)
        }
    }

    @MainActor
    func testActiveClaudeSessionEmitsActivitySneakPeekAndTracksRuntime() {
        let now = MutableDateProvider(Date(timeIntervalSince1970: 0))
        let bus = EventBus()
        let plugin = ClaudePlugin(nowProvider: { now.value })
        let recorder = SplitEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-active-sneak",
                rawJSON: """
                {
                  "hook_event_name": "UserPromptSubmit",
                  "session_id": "claude-active-sneak-session",
                  "prompt": "Create temporary file"
                }
                """
            ),
            respond: { _ in }
        )

        guard case let .sneakPeekRequested(request)? = recorder.events.first else {
            XCTFail("expected Claude activity sneak peek request")
            bus.unsubscribe(token)
            return
        }

        now.value = Date(timeIntervalSince1970: 12)

        let activity = plugin.currentCompactActivity
        XCTAssertEqual(request.pluginID, "claude")
        XCTAssertEqual(request.kind, .activity)
        XCTAssertEqual(request.priority, SneakPeekRequestPriority.aiActivity)
        XCTAssertTrue(request.isInteractive)
        XCTAssertEqual(activity?.host, .claude)
        XCTAssertEqual(activity?.approvalCount, 0)
        XCTAssertEqual(activity?.sessionTitle, "Create temporary file")
        XCTAssertEqual(activity?.runtimeDurationText, "12s")

        bus.unsubscribe(token)
    }

    @MainActor
    func testClaudeActivitySneakDismissesWhenSessionStops() {
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
                requestID: "claude-active-before-stop",
                rawJSON: """
                {
                  "hook_event_name": "UserPromptSubmit",
                  "session_id": "claude-stop-activity-session",
                  "prompt": "Create temporary file"
                }
                """
            ),
            respond: { _ in }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-stop-after-activity",
                rawJSON: """
                {
                  "hook_event_name": "Stop",
                  "session_id": "claude-stop-activity-session"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(recorder.events.contains { event in
            if case .sneakPeekRequested = event { return true }
            return false
        })
        XCTAssertTrue(recorder.events.contains { event in
            if case .dismissSneakPeek = event { return true }
            return false
        })
        XCTAssertNil(plugin.currentCompactActivity)

        bus.unsubscribe(token)
    }

    @MainActor
    func testManualStopSessionFreezesRuntimeAndDismissesActivitySneakPeek() {
        let now = MutableDateProvider(Date(timeIntervalSince1970: 0))
        let bus = EventBus()
        let plugin = ClaudePlugin(nowProvider: { now.value })
        let recorder = SplitEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-manual-stop-active",
                rawJSON: """
                {
                  "hook_event_name": "UserPromptSubmit",
                  "session_id": "claude-manual-stop-session",
                  "prompt": "Investigate stale session"
                }
                """
            ),
            respond: { _ in }
        )

        now.value = Date(timeIntervalSince1970: 12)
        XCTAssertTrue(plugin.stopSession(id: "claude-manual-stop-session"))
        now.value = Date(timeIntervalSince1970: 30)

        let summary = plugin.expandedSessionSummaries.first
        XCTAssertNil(plugin.currentCompactActivity)
        XCTAssertEqual(summary?.id, "claude-manual-stop-session")
        XCTAssertEqual(summary?.phase, .completed)
        XCTAssertEqual(summary?.runtimeDurationText, "12s")
        XCTAssertTrue(recorder.events.contains { event in
            if case .dismissSneakPeek = event { return true }
            return false
        })

        bus.unsubscribe(token)
    }

    @MainActor
    func testPermissionRequestDoesNotEmitSneakPeekWhenApprovalSneakSettingIsDisabled() {
        let previousValue = SettingsStore.shared.approvalSneakNotificationsEnabled
        let previousActivityValue = SettingsStore.shared.activitySneakPreviewsHidden
        SettingsStore.shared.approvalSneakNotificationsEnabled = false
        SettingsStore.shared.activitySneakPreviewsHidden = true
        defer {
            SettingsStore.shared.approvalSneakNotificationsEnabled = previousValue
            SettingsStore.shared.activitySneakPreviewsHidden = previousActivityValue
        }

        let bus = EventBus()
        let plugin = ClaudePlugin()
        let recorder = SplitEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        Self.sendPreToolUse(
            plugin: plugin,
            requestID: "claude-pre-disabled",
            sessionID: "claude-session-disabled",
            command: "echo hidden",
            toolUseID: "toolu_disabled"
        )
        recorder.events.removeAll()
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
        Self.sendPreToolUse(
            plugin: plugin,
            requestID: "claude-pre-reenable",
            sessionID: "claude-session-reenable",
            command: "echo reenable",
            toolUseID: "toolu_reenable"
        )
        recorder.events.removeAll()
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

        XCTAssertFalse(recorder.events.contains { event in
            if case let .sneakPeekRequested(request) = event, request.kind == .attention {
                return true
            }
            return false
        })

        SettingsStore.shared.approvalSneakNotificationsEnabled = true

        let attentionRequest = recorder.events.compactMap { event -> SneakPeekRequest? in
            guard case let .sneakPeekRequested(request) = event, request.kind == .attention else {
                return nil
            }
            return request
        }.first
        guard let request = attentionRequest else {
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
    func testPreToolUseCreatesActivitySneakPeekWithoutApproval() {
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
        guard case let .sneakPeekRequested(request)? = recorder.events.first else {
            XCTFail("expected Claude activity sneak peek request")
            bus.unsubscribe(token)
            return
        }
        XCTAssertEqual(request.pluginID, "claude")
        XCTAssertEqual(request.kind, .activity)
        XCTAssertEqual(String(data: responseBox.data ?? Data(), encoding: .utf8), "{}")

        bus.unsubscribe(token)
    }

    @MainActor
    func testPostToolUseKeepsActivitySneakPeekUntilStop() {
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
                requestID: "claude-posttool-prompt",
                rawJSON: """
                {
                  "hook_event_name": "UserPromptSubmit",
                  "session_id": "claude-posttool-session",
                  "prompt": "Run a command and continue"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(recorder.events.contains { event in
            if case .sneakPeekRequested = event { return true }
            return false
        })

        recorder.events.removeAll()

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-posttool-finished",
                rawJSON: """
                {
                  "hook_event_name": "PostToolUse",
                  "session_id": "claude-posttool-session",
                  "tool_name": "Bash",
                  "tool_input": { "command": "ls -la" }
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertFalse(recorder.events.contains { event in
            if case .dismissSneakPeek = event { return true }
            return false
        })
        XCTAssertNotNil(plugin.preview(context: Self.previewContext))
        XCTAssertEqual(plugin.currentCompactActivity?.label, "Working")

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-posttool-stop",
                rawJSON: """
                {
                  "hook_event_name": "Stop",
                  "session_id": "claude-posttool-session"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(recorder.events.contains { event in
            if case .dismissSneakPeek = event { return true }
            return false
        })
        XCTAssertNil(plugin.currentCompactActivity)

        bus.unsubscribe(token)
    }

    @MainActor
    func testAskUserQuestionPreToolUseShowsQuestionAndReturnsUpdatedInputAnswer() throws {
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
                requestID: "claude-question",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "claude-question-session",
                  "tool_name": "AskUserQuestion",
                  "tool_input": {
                    "questions": [
                      {
                        "question": "这次重设计的覆盖范围是？",
                        "header": "Scope",
                        "options": [
                          { "label": "全套 UI 一次性重做（推荐）" },
                          { "label": "只做刘海展开面板" }
                        ]
                      }
                    ]
                  }
                }
                """
            ),
            respond: { data in
                responseBox.data = data
            }
        )

        guard case let .sneakPeekRequested(request)? = recorder.events.first else {
            XCTFail("expected AskUserQuestion sneak peek request")
            bus.unsubscribe(token)
            return
        }

        let approval = try XCTUnwrap(plugin.pendingApprovals.first)
        XCTAssertEqual(request.pluginID, "claude")
        XCTAssertEqual(request.kind, .attention)
        XCTAssertEqual(approval.eventType, .preToolUse)
        XCTAssertEqual(approval.payload.title, "Claude needs your input")
        XCTAssertEqual(approval.payload.claudeQuestions.first?.question, "这次重设计的覆盖范围是？")
        XCTAssertEqual(approval.payload.claudeQuestions.first?.options.map(\.label), [
            "全套 UI 一次性重做（推荐）",
            "只做刘海展开面板",
        ])

        let answerInput = approval.payload.updatedInput(answering: [
            "这次重设计的覆盖范围是？": "只做刘海展开面板",
        ])
        let action = ApprovalAction(
            id: "claude-question-answer",
            title: "Submit",
            style: .primary,
            payload: .claude(
                ApprovalDecision(
                    behavior: .allow,
                    updatedInput: answerInput
                )
            )
        )

        plugin.respond(to: "claude-question", with: action)

        guard
            let data = responseBox.data,
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = parsed["hookSpecificOutput"] as? [String: Any],
            let updatedInput = output["updatedInput"] as? [String: Any],
            let answers = updatedInput["answers"] as? [String: String]
        else {
            XCTFail("expected AskUserQuestion updatedInput response")
            bus.unsubscribe(token)
            return
        }

        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertEqual(answers["这次重设计的覆盖范围是？"], "只做刘海展开面板")
        XCTAssertTrue(plugin.pendingApprovals.isEmpty)

        bus.unsubscribe(token)
    }

    @MainActor
    func testPendingApprovalUsesCodexStyleExpandedSummaryPresentation() {
        let bus = EventBus()
        let plugin = ClaudePlugin()

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-summary-prompt",
                rawJSON: """
                {
                  "hook_event_name": "UserPromptSubmit",
                  "session_id": "claude-session-summary",
                  "prompt": "Review the release notes"
                }
                """
            ),
            respond: { _ in }
        )
        Self.sendPreToolUse(
            plugin: plugin,
            requestID: "claude-summary-pretool",
            sessionID: "claude-session-summary",
            command: "git diff --stat",
            toolUseID: "toolu_summary"
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-summary-approval",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-summary",
                  "tool_name": "Bash",
                  "tool_input": { "command": "git diff --stat" }
                }
                """
            ),
            respond: { _ in }
        )

        let summary = try! XCTUnwrap(plugin.expandedSessionSummaries.first)
        XCTAssertEqual(summary.title, "Review the release notes")
        XCTAssertEqual(summary.subtitle, "Action Needed")
        XCTAssertEqual(summary.approvalCount, 0)
        XCTAssertEqual(summary.approvalRequestID, "claude-summary-approval")
    }

    @MainActor
    func testPostToolUseWithCachedToolUseIDClearsOnlyMatchingParallelApproval() {
        let bus = EventBus()
        let plugin = ClaudePlugin()
        let firstResponseBox = SplitResponseBox()
        let secondResponseBox = SplitResponseBox()
        let firstPreToolResponseBox = SplitResponseBox()
        let secondPreToolResponseBox = SplitResponseBox()
        let postToolResponseBox = SplitResponseBox()

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-parallel-pretool-one",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "claude-session-parallel",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo one" },
                  "tool_use_id": "toolu_one"
                }
                """
            ),
            respond: { data in firstPreToolResponseBox.data = data }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-parallel-pretool-two",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "claude-session-parallel",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo two" },
                  "tool_use_id": "toolu_two"
                }
                """
            ),
            respond: { data in secondPreToolResponseBox.data = data }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-parallel-one",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-parallel",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo one" }
                }
                """
            ),
            respond: { data in firstResponseBox.data = data }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-parallel-two",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-parallel",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo two" }
                }
                """
            ),
            respond: { data in secondResponseBox.data = data }
        )

        XCTAssertEqual(
            plugin.pendingApprovals.map(\.requestID),
            ["claude-parallel-one", "claude-parallel-two"]
        )
        XCTAssertEqual(plugin.pendingApprovals.first?.payload.toolUseID, "toolu_one")
        XCTAssertEqual(plugin.pendingApprovals.last?.payload.toolUseID, "toolu_two")
        XCTAssertEqual(String(data: firstPreToolResponseBox.data ?? Data(), encoding: .utf8), "{}")
        XCTAssertEqual(String(data: secondPreToolResponseBox.data ?? Data(), encoding: .utf8), "{}")
        XCTAssertNil(firstResponseBox.data)
        XCTAssertNil(secondResponseBox.data)

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-parallel-posttool-one",
                rawJSON: """
                {
                  "hook_event_name": "PostToolUse",
                  "session_id": "claude-session-parallel",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo rewritten by shell" },
                  "tool_use_id": "toolu_one"
                }
                """
            ),
            respond: { data in postToolResponseBox.data = data }
        )

        XCTAssertEqual(
            plugin.pendingApprovals.map(\.requestID),
            ["claude-parallel-two"]
        )
        XCTAssertEqual(String(data: firstResponseBox.data ?? Data(), encoding: .utf8), "{}")
        XCTAssertNil(secondResponseBox.data)
        XCTAssertEqual(String(data: postToolResponseBox.data ?? Data(), encoding: .utf8), "{}")
    }

    @MainActor
    func testPostToolUseWithDifferentToolUseIDDoesNotClearByMatchingCommand() {
        let plugin = ClaudePlugin()
        let permissionResponseBox = SplitResponseBox()

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-pretool-with-id",
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "claude-session-strict-id",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo exact only" },
                  "tool_use_id": "toolu_expected"
                }
                """
            ),
            respond: { _ in }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-permission-with-id",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-strict-id",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo exact only" }
                }
                """
            ),
            respond: { data in permissionResponseBox.data = data }
        )

        XCTAssertEqual(plugin.pendingApprovals.map(\.requestID), ["claude-permission-with-id"])
        XCTAssertEqual(plugin.pendingApprovals.first?.payload.toolUseID, "toolu_expected")

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-posttool-wrong-id",
                rawJSON: """
                {
                  "hook_event_name": "PostToolUse",
                  "session_id": "claude-session-strict-id",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo exact only" },
                  "tool_use_id": "toolu_other"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertEqual(plugin.pendingApprovals.map(\.requestID), ["claude-permission-with-id"])
        XCTAssertNil(permissionResponseBox.data)
    }

    @MainActor
    func testPermissionRequestWithoutCorrelatedToolUseIDDoesNotCreatePendingApproval() {
        let plugin = ClaudePlugin()
        let permissionResponseBox = SplitResponseBox()

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-permission-without-id",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-no-tool-id",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo native only" }
                }
                """
            ),
            respond: { data in permissionResponseBox.data = data }
        )

        XCTAssertTrue(plugin.pendingApprovals.isEmpty)
        XCTAssertEqual(String(data: permissionResponseBox.data ?? Data(), encoding: .utf8), "{}")
        XCTAssertEqual(plugin.sessions.first?.activityLabel, "Waiting Approval")
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
    func testConnectedOnlyClaudeSessionsAreHiddenFromExpandedSummaries() {
        let bus = EventBus()
        let plugin = ClaudePlugin()

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-connected-only-1",
                rawJSON: """
                {
                  "hook_event_name": "SessionStart",
                  "session_id": "claude-connected-only-1"
                }
                """
            ),
            respond: { _ in }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-connected-only-2",
                rawJSON: """
                {
                  "hook_event_name": "SessionStart",
                  "session_id": "claude-connected-only-2"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(plugin.sessions.isEmpty)
        XCTAssertTrue(plugin.expandedSessionSummaries.isEmpty)
    }

    @MainActor
    func testStoppedClaudeSessionWithUserActivityRemainsVisibleButConnectedOnlySessionsStayHidden() {
        let bus = EventBus()
        let plugin = ClaudePlugin()

        plugin.activate(bus: bus)
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-hidden-connected",
                rawJSON: """
                {
                  "hook_event_name": "SessionStart",
                  "session_id": "claude-hidden-connected"
                }
                """
            ),
            respond: { _ in }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-active-prompt",
                rawJSON: """
                {
                  "hook_event_name": "UserPromptSubmit",
                  "session_id": "claude-active-session",
                  "prompt": "Run again"
                }
                """
            ),
            respond: { _ in }
        )
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-active-stop",
                rawJSON: """
                {
                  "hook_event_name": "Stop",
                  "session_id": "claude-active-session"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertEqual(plugin.sessions.map(\.id), ["claude-active-session"])
        XCTAssertEqual(plugin.expandedSessionSummaries.map(\.id), ["claude-active-session"])
        XCTAssertEqual(plugin.expandedSessionSummaries.first?.title, "Run again")
        XCTAssertEqual(plugin.expandedSessionSummaries.first?.phase, .completed)
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
            Self.sendPreToolUse(
                plugin: plugin,
                requestID: "claude-long-pretool",
                sessionID: "claude-session-long-preview",
                command: longCommand,
                toolUseID: "toolu_long_preview"
            )
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
    func testHandleDisconnectClearsPendingApprovalAndSneakPeek() {
        let bus = EventBus()
        let plugin = ClaudePlugin()
        let recorder = SplitEventRecorder()
        let permissionResponseBox = SplitResponseBox()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        Self.sendPreToolUse(
            plugin: plugin,
            requestID: "claude-disconnect-pretool",
            sessionID: "claude-session-disconnect",
            command: "echo disconnect",
            toolUseID: "toolu_disconnect"
        )
        recorder.events.removeAll()
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-disconnect-permission",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-disconnect",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo disconnect" }
                }
                """
            ),
            respond: { data in
                permissionResponseBox.data = data
            }
        )

        XCTAssertEqual(plugin.pendingApprovals.map(\.requestID), ["claude-disconnect-permission"])

        plugin.handleDisconnect(requestID: "claude-disconnect-permission")

        XCTAssertTrue(plugin.pendingApprovals.isEmpty)
        XCTAssertNil(permissionResponseBox.data)
        XCTAssertTrue(recorder.events.contains { event in
            if case .dismissSneakPeek = event { return true }
            return false
        })

        bus.unsubscribe(token)
    }

    @MainActor
    func testStopEventReleasesHeldResponderAndClearsPendingApprovalForSession() {
        let bus = EventBus()
        let plugin = ClaudePlugin()
        let recorder = SplitEventRecorder()
        let permissionResponseBox = SplitResponseBox()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        Self.sendPreToolUse(
            plugin: plugin,
            requestID: "claude-stop-pretool",
            sessionID: "claude-session-stop-pending",
            command: "echo deny-in-claude-desktop",
            toolUseID: "toolu_stop_pending"
        )
        recorder.events.removeAll()
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-stop-permission",
                rawJSON: """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "claude-session-stop-pending",
                  "tool_name": "Bash",
                  "tool_input": { "command": "echo deny-in-claude-desktop" }
                }
                """
            ),
            respond: { data in
                permissionResponseBox.data = data
            }
        )

        XCTAssertEqual(plugin.pendingApprovals.map(\.requestID), ["claude-stop-permission"])
        XCTAssertNil(permissionResponseBox.data)
        XCTAssertTrue(recorder.events.contains { event in
            if case .sneakPeekRequested = event { return true }
            return false
        })

        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: "claude-stop-event",
                rawJSON: """
                {
                  "hook_event_name": "Stop",
                  "session_id": "claude-session-stop-pending"
                }
                """
            ),
            respond: { _ in }
        )

        XCTAssertTrue(plugin.pendingApprovals.isEmpty)
        XCTAssertEqual(String(data: permissionResponseBox.data ?? Data(), encoding: .utf8), "{}")
        XCTAssertTrue(recorder.events.contains { event in
            if case .dismissSneakPeek = event { return true }
            return false
        })

        bus.unsubscribe(token)
    }

    @MainActor
    func testDenyReturnsDenyAndClearsPendingApproval() {
        let plugin = ClaudePlugin()
        let responseBox = SplitResponseBox()

        Self.sendPreToolUse(
            plugin: plugin,
            requestID: "claude-deny-pretool",
            sessionID: "claude-session-deny-feedback",
            command: "rm -rf /tmp/demo",
            toolUseID: "toolu_deny_feedback"
        )
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

    @MainActor
    static func sendPreToolUse(
        plugin: ClaudePlugin,
        requestID: String,
        sessionID: String,
        command: String,
        toolUseID: String
    ) {
        plugin.handle(
            frame: BridgeFrame(
                host: .claude,
                requestID: requestID,
                rawJSON: """
                {
                  "hook_event_name": "PreToolUse",
                  "session_id": "\(sessionID)",
                  "tool_name": "Bash",
                  "tool_input": { "command": "\(command)" },
                  "tool_use_id": "\(toolUseID)"
                }
                """
            ),
            respond: { _ in }
        )
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

private final class MutableDateProvider: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}
