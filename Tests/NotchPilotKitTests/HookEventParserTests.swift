import XCTest
@testable import NotchPilotKit

final class HookEventParserTests: XCTestCase {
    func testClaudePermissionRequestBecomesInteractiveEnvelope() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-1",
            rawJSON: """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "claude-session",
              "tool_name": "Bash",
              "tool_input": {
                "command": "rm -rf /tmp/demo",
                "description": "Remove the demo directory"
              },
              "permission_suggestions": [
                {
                  "type": "addRules",
                  "rules": [{ "toolName": "Bash", "ruleContent": "rm -rf /tmp/demo" }],
                  "behavior": "allow",
                  "destination": "localSettings"
                }
              ],
              "capabilities": { "supports_persistent_rules": true }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.host, .claude)
        XCTAssertEqual(envelope.sessionID, "claude-session")
        XCTAssertEqual(envelope.eventType, .permissionRequest)
        XCTAssertTrue(envelope.needsResponse)
        XCTAssertTrue(envelope.capabilities.supportsPersistentRules)

        guard case let .permissionRequest(payload) = envelope.payload else {
            XCTFail("expected permission request payload")
            return
        }

        XCTAssertEqual(payload.toolName, "Bash")
        XCTAssertEqual(payload.description, "Remove the demo directory")
        XCTAssertEqual(payload.title, "Allow Claude to run Remove the demo directory?")
        XCTAssertEqual(payload.previewText, "rm -rf /tmp/demo")
        XCTAssertEqual(payload.permissionSuggestions.count, 1)
    }

    func testNotificationEventReturnsNeedsResponseFalse() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-3",
            origin: AISessionLaunchContext(
                processIdentifier: 4242,
                bundleIdentifier: "com.apple.Terminal",
                terminalIdentifier: "ttys003",
                codexClientID: nil
            ),
            rawJSON: """
            {
              "hook_event_name": "PostToolUse",
              "session_id": "claude-session",
              "tool_name": "Bash",
              "tool_input": { "command": "pwd" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.eventType, .postToolUse)
        XCTAssertFalse(envelope.needsResponse)
        XCTAssertEqual(envelope.launchContext?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(envelope.launchContext?.terminalIdentifier, "ttys003")
    }

    func testPermissionPayloadExtractsCommandFileAndDiffPreview() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-3",
            rawJSON: """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "claude-session",
              "tool_name": "Edit",
              "tool_input": {
                "file_path": "/tmp/demo.txt",
                "command": "cat /tmp/demo.txt",
                "content": "new file contents"
              }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        guard case let .permissionRequest(payload) = envelope.payload else {
            return XCTFail("expected permission request payload")
        }

        XCTAssertEqual(payload.previewText, "cat /tmp/demo.txt")
        XCTAssertEqual(payload.command, "cat /tmp/demo.txt")
        XCTAssertEqual(payload.filePath, "/tmp/demo.txt")
        XCTAssertEqual(payload.diffContent, "new file contents")
    }

    func testPermissionPayloadLoadsCurrentFileContentsForPreApprovalDiff() throws {
        let parser = HookEventParser(loadFileContent: { path in
            XCTAssertEqual(path, "/tmp/demo.txt")
            return "old file contents"
        })

        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-4",
            rawJSON: """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "claude-session",
              "tool_name": "Edit",
              "tool_input": {
                "file_path": "/tmp/demo.txt",
                "new_string": "updated file contents"
              }
            }
            """
        )

        let envelope = try parser.parse(frame: frame)

        guard case let .permissionRequest(payload) = envelope.payload else {
            return XCTFail("expected permission request payload")
        }

        XCTAssertEqual(payload.filePath, "/tmp/demo.txt")
        XCTAssertEqual(payload.originalContent, "old file contents")
        XCTAssertEqual(payload.diffContent, "updated file contents")
    }

    func testInvalidJSONThrows() {
        let frame = BridgeFrame(host: .claude, requestID: "bad", rawJSON: "{not-json")

        XCTAssertThrowsError(try HookEventParser().parse(frame: frame))
    }

    func testPreToolUseReadToolDoesNotRequireResponse() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-read",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "session_id": "claude-session",
              "tool_name": "Read",
              "tool_input": { "file_path": "/tmp/demo.txt" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.eventType, .preToolUse)
        XCTAssertFalse(envelope.needsResponse)
    }

    func testPreToolUseAskUserQuestionRequiresResponseAndExtractsQuestionOptions() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-question",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "session_id": "claude-session",
              "tool_name": "AskUserQuestion",
              "tool_input": {
                "questions": [
                  {
                    "question": "这次重设计的覆盖范围是？",
                    "header": "Scope",
                    "options": [
                      {
                        "label": "全套 UI 一次性重做（推荐）",
                        "description": "刘海展开面板 + sneak 紧凑态 + 设置窗口"
                      },
                      {
                        "label": "只做刘海展开面板",
                        "description": "先把 expanded notch 做好"
                      }
                    ],
                    "multiSelect": false
                  }
                ]
              }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.eventType, .preToolUse)
        XCTAssertTrue(envelope.needsResponse)

        guard case let .permissionRequest(payload) = envelope.payload else {
            return XCTFail("expected AskUserQuestion to become an interactive payload")
        }

        XCTAssertEqual(payload.title, "Claude needs your input")
        XCTAssertEqual(payload.previewText, "这次重设计的覆盖范围是？")
        XCTAssertEqual(payload.claudeQuestions.count, 1)
        XCTAssertEqual(payload.claudeQuestions.first?.header, "Scope")
        XCTAssertEqual(payload.claudeQuestions.first?.question, "这次重设计的覆盖范围是？")
        XCTAssertEqual(payload.claudeQuestions.first?.options.map(\.label), [
            "全套 UI 一次性重做（推荐）",
            "只做刘海展开面板",
        ])
        XCTAssertEqual(
            payload.claudeQuestions.first?.options.first?.description,
            "刘海展开面板 + sneak 紧凑态 + 设置窗口"
        )
        XCTAssertEqual(payload.toolInput?.objectValue?["questions"]?.arrayValue?.count, 1)
    }

    func testPermissionRequestWebFetchRequiresResponseAndExtractsDomain() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-web-fetch",
            rawJSON: """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "claude-session",
              "tool_name": "WebFetch",
              "tool_input": { "url": "https://docs.anthropic.com/en/docs/claude-code/hooks" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertTrue(envelope.needsResponse)

        guard case let .permissionRequest(payload) = envelope.payload else {
            return XCTFail("expected permission request payload")
        }

        XCTAssertEqual(payload.toolKind, .webFetch)
        XCTAssertEqual(payload.webFetchURL, "https://docs.anthropic.com/en/docs/claude-code/hooks")
        XCTAssertEqual(payload.webFetchDomain, "docs.anthropic.com")
    }

    func testPreToolUseBashDoesNotRequireResponseOrApprovalPayload() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-pretool-bash",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "session_id": "claude-session",
              "tool_name": "Bash",
              "tool_input": { "command": "ls -la" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertFalse(envelope.needsResponse)
        guard case let .generic(values) = envelope.payload else {
            return XCTFail("expected PreToolUse to be a non-approval activity payload")
        }
        XCTAssertEqual(values["tool_name"], "Bash")
    }

    func testUserPromptSubmitDoesNotInjectTranscriptSessionTitle() throws {
        let transcriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-session-title-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: transcriptURL)
        }

        try """
        {"type":"user","message":{"role":"user","content":"请帮我修复审批同步问题"}}
        {"type":"assistant","sessionTitle":"Fix Approval Sync"}
        """.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-title-transcript",
            rawJSON: """
            {
              "hook_event_name": "UserPromptSubmit",
              "session_id": "claude-session-title",
              "transcript_path": "\(transcriptURL.path)",
              "prompt": "请帮我修复审批同步问题"
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        guard case let .generic(values) = envelope.payload else {
            return XCTFail("expected generic user prompt payload")
        }
        XCTAssertEqual(values["prompt"], "请帮我修复审批同步问题")
        XCTAssertNil(values["session_title"])
    }

    func testPreToolUseEditToolDoesNotRequireResponseInDefaultMode() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-edit",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "session_id": "claude-session",
              "tool_name": "Edit",
              "tool_input": { "file_path": "/tmp/demo.txt", "new_string": "hi" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertFalse(envelope.needsResponse)
    }

    func testPreToolUseBashSkipsResponseInBypassMode() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-bypass",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "session_id": "claude-session",
              "tool_name": "Bash",
              "permission_mode": "bypassPermissions",
              "tool_input": { "command": "ls" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertFalse(envelope.needsResponse)
    }

    func testPreToolUseBashInPlanModeSkipsResponse() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-plan",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "session_id": "claude-session",
              "tool_name": "Bash",
              "permission_mode": "plan",
              "tool_input": { "command": "ls" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertFalse(envelope.needsResponse)
    }

    func testPermissionRequestAlwaysRequiresResponseEvenForReadOnlyTools() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-perm-read",
            rawJSON: """
            {
              "hook_event_name": "PermissionRequest",
              "session_id": "claude-session",
              "tool_name": "Read",
              "tool_input": { "file_path": "/tmp/demo.txt" }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertTrue(envelope.needsResponse)
    }

    // MARK: - Devin Local

    /// Devin Local hook payloads use the Claude-compatible schema but never include
    /// a `session_id` field (verified empirically against `devin acp` running inside
    /// Windsurf). The bridge script (`notch-bridge.py`) compensates by injecting
    /// `session_id: notchpilot-agent-pid-<pid>` derived from the Devin acp main
    /// process PID. This test guarantees the parser carries that fallback through.
    func testDevinFrameKeepsBridgeInjectedSessionID() throws {
        let frame = BridgeFrame(
            host: .devin,
            requestID: "req-devin-1",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "tool_name": "exec",
              "tool_input": { "command": "ls" },
              "tool_use_id": "toolu_bdrk_01Pk9yTFDRTeeawxwx12A41B",
              "session_id": "notchpilot-agent-pid-30716"
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.host, .devin)
        XCTAssertEqual(envelope.sessionID, "notchpilot-agent-pid-30716")
        XCTAssertEqual(envelope.eventType, .preToolUse)
        XCTAssertFalse(envelope.needsResponse)
    }

    /// If for some reason the bridge could not inject a session_id (e.g. malformed
    /// JSON), the parser must still fall back to `frame.requestID` so each Devin
    /// invocation does not crash the pipeline. We accept a per-tool-call grouping
    /// in that pathological case — the bridge layer is responsible for stable
    /// sessions, not the parser.
    func testDevinFrameFallsBackToRequestIDWhenSessionIDMissing() throws {
        let frame = BridgeFrame(
            host: .devin,
            requestID: "fallback-uuid",
            rawJSON: """
            {
              "hook_event_name": "PostToolUse",
              "tool_name": "exec",
              "tool_input": { "command": "pwd" },
              "tool_response": { "success": true, "output": "/tmp", "error": null }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.host, .devin)
        XCTAssertEqual(envelope.sessionID, "fallback-uuid")
        XCTAssertEqual(envelope.eventType, .postToolUse)
    }
}
