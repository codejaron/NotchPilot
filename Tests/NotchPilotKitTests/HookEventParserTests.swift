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

    func testPreToolUseWebFetchRequiresResponseAndExtractsDomain() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-web-fetch",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
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

    func testPreToolUseEditToolRequiresResponseInDefaultMode() throws {
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

        XCTAssertTrue(envelope.needsResponse)
    }

    func testPreToolUseEditToolSkipsResponseInAcceptEditsMode() throws {
        let frame = BridgeFrame(
            host: .claude,
            requestID: "req-accept-edits",
            rawJSON: """
            {
              "hook_event_name": "PreToolUse",
              "session_id": "claude-session",
              "tool_name": "Edit",
              "permission_mode": "acceptEdits",
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
}
