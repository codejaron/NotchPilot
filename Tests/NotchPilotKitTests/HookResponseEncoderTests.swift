import XCTest
@testable import NotchPilotKit

final class HookResponseEncoderTests: XCTestCase {
    func testClaudePermissionRequestAllowEmitsAllowDecisionPayload() throws {
        let data = try HookResponseEncoder().encode(
            decision: .allowOnce,
            for: .claude,
            eventType: .permissionRequest
        )

        guard
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = parsed["hookSpecificOutput"] as? [String: Any],
            let outputDecision = output["decision"] as? [String: Any]
        else {
            return XCTFail("expected PermissionRequest decision")
        }

        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(outputDecision["behavior"] as? String, "allow")
        XCTAssertNil(outputDecision["updatedPermissions"])
    }

    func testClaudePermissionRequestAllowCanEchoUpdatedPermissions() throws {
        let update: JSONValue = .object([
            "type": .string("addRules"),
            "rules": .array([
                .object([
                    "toolName": .string("Bash"),
                    "ruleContent": .string("npm test"),
                ]),
            ]),
            "behavior": .string("allow"),
            "destination": .string("localSettings"),
        ])
        let decision = ApprovalDecision(behavior: .allow, permissionUpdates: [update])

        let data = try HookResponseEncoder().encode(
            decision: decision,
            for: .claude,
            eventType: .permissionRequest
        )

        guard
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = parsed["hookSpecificOutput"] as? [String: Any],
            let outputDecision = output["decision"] as? [String: Any],
            let updatedPermissions = outputDecision["updatedPermissions"] as? [[String: Any]]
        else {
            return XCTFail("expected updatedPermissions in PermissionRequest response")
        }

        XCTAssertEqual(outputDecision["behavior"] as? String, "allow")
        let destination = updatedPermissions.first?["destination"] as? String
        XCTAssertEqual(destination, "localSettings")
    }

    func testClaudePermissionRequestDenyUsesOfficialMessageField() throws {
        let decision = ApprovalDecision(
            behavior: .deny,
            feedbackText: "Please use ripgrep instead"
        )

        let data = try HookResponseEncoder().encode(
            decision: decision,
            for: .claude,
            eventType: .permissionRequest
        )

        guard
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = parsed["hookSpecificOutput"] as? [String: Any],
            let outputDecision = output["decision"] as? [String: Any]
        else {
            return XCTFail("expected PermissionRequest decision")
        }

        XCTAssertEqual(outputDecision["behavior"] as? String, "deny")
        XCTAssertEqual(outputDecision["message"] as? String, "Please use ripgrep instead")
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

    func testClaudePreToolUseAllowCanReturnUpdatedAskUserQuestionInput() throws {
        let decision = ApprovalDecision(
            behavior: .allow,
            updatedInput: .object([
                "questions": .array([
                    .object([
                        "question": .string("这次重设计的覆盖范围是？"),
                        "options": .array([
                            .object(["label": .string("全套 UI 一次性重做（推荐）")]),
                        ]),
                    ]),
                ]),
                "answers": .object([
                    "这次重设计的覆盖范围是？": .string("全套 UI 一次性重做（推荐）"),
                ]),
            ])
        )

        let data = try HookResponseEncoder().encode(
            decision: decision,
            for: .claude,
            eventType: .preToolUse
        )

        guard
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = parsed["hookSpecificOutput"] as? [String: Any],
            let updatedInput = output["updatedInput"] as? [String: Any],
            let answers = updatedInput["answers"] as? [String: String]
        else {
            return XCTFail("expected PreToolUse updatedInput")
        }

        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertEqual(answers["这次重设计的覆盖范围是？"], "全套 UI 一次性重做（推荐）")
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
