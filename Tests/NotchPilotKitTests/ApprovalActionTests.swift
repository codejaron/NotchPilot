import XCTest
@testable import NotchPilotKit

final class ApprovalActionTests: XCTestCase {
    func testPermissionSuggestionCreatesOfficialPersistentAction() throws {
        let suggestion: JSONValue = .object([
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
        let actions = ApprovalAction.claudeActions(
            toolKind: .bash,
            toolName: "Bash",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil,
            permissionSuggestions: [suggestion]
        )

        let action = try XCTUnwrap(actions.first(where: { $0.id == "claude-allow-persist" }))
        guard case let .claude(decision) = action.payload else {
            return XCTFail("expected Claude decision")
        }

        XCTAssertEqual(decision.permissionUpdates, [suggestion])
        XCTAssertNil(decision.sessionRule)
        XCTAssertNil(decision.persistRule)
        XCTAssertEqual(actions.map(\.title), [
            "No",
            "Yes",
            "Yes, and don't ask again for Bash(npm test) commands in this project",
        ])
        XCTAssertEqual(actions.map(\.style), [.outline, .outline, .primary])
    }

    func testPermissionSuggestionUsesCwdInLabel() throws {
        let suggestion: JSONValue = .object([
            "type": .string("addRules"),
            "rules": .array([
                .object([
                    "toolName": .string("WebSearch"),
                ]),
            ]),
            "behavior": .string("allow"),
            "destination": .string("localSettings"),
        ])
        let actions = ApprovalAction.claudeActions(
            toolKind: .webSearch,
            toolName: "WebSearch",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil,
            permissionSuggestions: [suggestion],
            cwd: "/Users/jaron/data/project/NotchPilot"
        )

        XCTAssertEqual(actions.map(\.title), [
            "No",
            "Yes",
            "Yes, and don't ask again for Web Search commands in /Users/jaron/data/project/NotchPilot",
        ])
    }

    func testSessionPermissionSuggestionUsesDontAskAgainLanguage() throws {
        let suggestion: JSONValue = .object([
            "type": .string("addRules"),
            "rules": .array([
                .object([
                    "toolName": .string("Bash"),
                    "ruleContent": .string("npm list *"),
                ]),
            ]),
            "behavior": .string("allow"),
            "destination": .string("session"),
        ])
        let actions = ApprovalAction.claudeActions(
            toolKind: .bash,
            toolName: "Bash",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil,
            permissionSuggestions: [suggestion]
        )

        XCTAssertEqual(actions.map(\.title), [
            "No",
            "Yes",
            "Yes, and don't ask again for Bash(npm list *) commands this session",
        ])
    }

    func testSetModeAcceptEditsSuggestionNamesModeInsteadOfGenericAllow() throws {
        let suggestion: JSONValue = .object([
            "type": .string("setMode"),
            "mode": .string("acceptEdits"),
            "destination": .string("session"),
        ])
        let actions = ApprovalAction.claudeActions(
            toolKind: .edit,
            toolName: "Edit",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil,
            permissionSuggestions: [suggestion]
        )

        XCTAssertEqual(actions.map(\.title), [
            "No",
            "Yes",
            "Yes, and accept edits this session",
        ])
    }

    func testDirectoryPermissionSuggestionUsesDirectoryLanguage() throws {
        let suggestion: JSONValue = .object([
            "type": .string("addDirectories"),
            "directories": .array([.string("/tmp")]),
            "destination": .string("localSettings"),
        ])
        let actions = ApprovalAction.claudeActions(
            toolKind: .bash,
            toolName: "Bash",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil,
            permissionSuggestions: [suggestion]
        )

        XCTAssertEqual(actions.map(\.title), [
            "No",
            "Yes",
            "Yes, and always allow directory access in this project",
        ])
    }

    func testNoPermissionSuggestionDoesNotInventPersistentAction() {
        let actions = ApprovalAction.claudeActions(
            toolKind: .edit,
            toolName: "Write",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil,
            permissionSuggestions: []
        )

        XCTAssertNil(actions.first(where: { $0.id == "claude-allow-persist" }))
        XCTAssertEqual(actions.map(\.title), ["No", "Yes"])
        XCTAssertEqual(actions.map(\.style), [.outline, .primary])
    }

    func testAskUserQuestionDoesNotUseGenericAllowDenyApprovalActions() {
        let actions = ApprovalAction.claudeActions(
            toolKind: .other,
            toolName: "AskUserQuestion",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil,
            permissionSuggestions: []
        )

        XCTAssertTrue(actions.isEmpty)
    }
}
