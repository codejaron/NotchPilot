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
              "tool_input": { "command": "rm -rf /tmp/demo" },
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
        XCTAssertEqual(payload.previewText, "rm -rf /tmp/demo")
    }

    func testCodexPermissionRequestWithoutPersistentRulesStaysNonPersistent() throws {
        let frame = BridgeFrame(
            host: .codex,
            requestID: "req-2",
            rawJSON: """
            {
              "event": "approval_request",
              "sessionId": "codex-session",
              "tool": {
                "name": "shell",
                "input": { "command": "ls -la" }
              },
              "capabilities": { "supportsPersistentRules": false }
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.eventType, .permissionRequest)
        XCTAssertTrue(envelope.needsResponse)
        XCTAssertFalse(envelope.capabilities.supportsPersistentRules)
    }

    func testNotificationEventReturnsNeedsResponseFalse() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-3",
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
    }

    func testUserPromptSubmitNormalizesPromptIntoGenericPayload() throws {
        let frame = BridgeFrame(
            host: .codex,
            requestID: "req-4",
            rawJSON: """
            {
              "event": "user_prompt_submit",
              "sessionId": "codex-session",
              "user_prompt": "Build a backend server with express"
            }
            """
        )

        let envelope = try HookEventParser().parse(frame: frame)

        XCTAssertEqual(envelope.eventType, .userPromptSubmit)
        XCTAssertFalse(envelope.needsResponse)

        guard case let .generic(values) = envelope.payload else {
            return XCTFail("expected generic payload")
        }

        XCTAssertEqual(values["prompt"], "Build a backend server with express")
    }

    func testPermissionPayloadExtractsCommandFileAndDiffPreview() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-5",
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
            requestID: "req-6",
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
}
