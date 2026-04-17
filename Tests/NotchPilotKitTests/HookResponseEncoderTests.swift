import XCTest
@testable import NotchPilotKit

final class HookResponseEncoderTests: XCTestCase {
    func testClaudePermissionRequestAllowEmitsAllowDecisionPayload() throws {
        let data = try HookResponseEncoder().encode(
            decision: .allowOnce,
            for: .claude,
            eventType: .permissionRequest
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(
            json,
            #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"},"reason":"Approved via NotchPilot"}}"#
        )
    }

    func testClaudePreToolUseAllowWithFeedbackPassesReasonThrough() throws {
        let decision = ApprovalDecision(behavior: .allow, feedbackText: "Looks good")
        let data = try HookResponseEncoder().encode(
            decision: decision,
            for: .claude,
            eventType: .preToolUse
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(
            json,
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Looks good"}}"#
        )
    }

    func testClaudePreToolUseDenyWithFeedbackPassesReasonThrough() throws {
        let decision = ApprovalDecision(behavior: .deny, feedbackText: "Please use ripgrep instead")
        let data = try HookResponseEncoder().encode(
            decision: decision,
            for: .claude,
            eventType: .preToolUse
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(
            json,
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Please use ripgrep instead"}}"#
        )
    }

    func testClaudePreToolUsePersistRuleTriggersRuleStoreAndAllows() throws {
        final class RuleRecorder: PermissionRuleWriting, @unchecked Sendable {
            var recorded: [ClaudePermissionRule] = []
            func appendAllowRule(_ rule: ClaudePermissionRule) throws {
                recorded.append(rule)
            }
        }

        let recorder = RuleRecorder()
        let encoder = HookResponseEncoder(permissionRuleStore: recorder)
        let decision = ApprovalDecision(
            behavior: .allow,
            persistRule: .bashPrefix("git status")
        )

        let data = try encoder.encode(decision: decision, for: .claude, eventType: .preToolUse)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(recorder.recorded, [.bashPrefix("git status")])
        XCTAssertTrue(json.contains(#""permissionDecision":"allow""#))
    }

    func testFeedbackWithSpecialCharactersIsEscapedInJSON() throws {
        let decision = ApprovalDecision(
            behavior: .deny,
            feedbackText: "Don't use \"rm -rf\"\nuse trash instead"
        )
        let data = try HookResponseEncoder().encode(
            decision: decision,
            for: .claude,
            eventType: .preToolUse
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        guard let jsonData = json.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let output = parsed["hookSpecificOutput"] as? [String: Any],
              let reason = output["permissionDecisionReason"] as? String
        else {
            return XCTFail("expected well-formed JSON")
        }
        XCTAssertEqual(reason, "Don't use \"rm -rf\"\nuse trash instead")
    }
}
