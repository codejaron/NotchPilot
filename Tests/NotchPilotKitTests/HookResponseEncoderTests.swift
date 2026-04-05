import XCTest
@testable import NotchPilotKit

final class HookResponseEncoderTests: XCTestCase {
    func testClaudePermissionRequestAllowUsesHookSpecificDecisionPayload() throws {
        let data = try HookResponseEncoder().encode(
            decision: .allowOnce,
            for: .claude,
            eventType: .permissionRequest
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(
            json,
            #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        )
    }

    func testClaudePreToolUsePersistentApprovalUsesPermissionDecisionEnvelope() throws {
        let data = try HookResponseEncoder().encode(
            decision: .persistAllowRule,
            for: .claude,
            eventType: .preToolUse
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(
            json,
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Always allowed via NotchPilot"}}"#
        )
    }

    func testCodexPreToolUseAllowFailsOpen() throws {
        let data = try HookResponseEncoder().encode(
            decision: .allowOnce,
            for: .codex,
            eventType: .preToolUse
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(json, "{}")
    }

    func testCodexPreToolUseDenyUsesSchemaValidHookSpecificOutput() throws {
        let data = try HookResponseEncoder().encode(
            decision: .denyOnce,
            for: .codex,
            eventType: .preToolUse
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(
            json,
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied via NotchPilot"}}"#
        )
    }
}
