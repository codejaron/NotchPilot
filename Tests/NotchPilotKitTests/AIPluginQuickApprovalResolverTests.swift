import XCTest
@testable import NotchPilotKit

final class AIPluginQuickApprovalResolverTests: XCTestCase {
    func testClaudeQuickApproveUsesOrdinaryAllowWhenPersistentAllowExists() throws {
        let persistentSuggestion: JSONValue = .object([
            "type": .string("setMode"),
            "mode": .string("dontAsk"),
            "destination": .string("session"),
        ])
        let approval = makeClaudeApproval(
            requestID: "claude-ordinary-allow",
            actions: ApprovalAction.claudeActions(
                toolKind: .bash,
                toolName: "Bash",
                bashCommandPrefix: nil,
                webFetchDomain: nil,
                mcpServer: nil,
                mcpTool: nil,
                permissionSuggestions: [persistentSuggestion]
            )
        )

        let quickActions = AIPluginQuickApprovalResolver.actions(for: approval)

        XCTAssertEqual(quickActions.approve?.claudeActionID, "claude-allow")
        XCTAssertEqual(quickActions.reject?.claudeActionID, "claude-deny")
    }

    func testClaudeQuickApproveDoesNotUsePersistentAllowWhenOrdinaryAllowIsMissing() {
        let approval = makeClaudeApproval(
            requestID: "claude-persistent-only",
            actions: [
                ApprovalAction(
                    id: "claude-allow-persist",
                    title: "Yes, and don't ask again",
                    style: .primary,
                    payload: .claude(
                        ApprovalDecision(
                            behavior: .allow,
                            permissionUpdates: [.object(["type": .string("setMode")])]
                        )
                    )
                ),
                ApprovalAction(
                    id: "claude-deny",
                    title: "No",
                    style: .outline,
                    payload: .claude(.denyOnce)
                ),
            ]
        )

        let quickActions = AIPluginQuickApprovalResolver.actions(for: approval)

        XCTAssertNil(quickActions.approve)
        XCTAssertEqual(quickActions.reject?.claudeActionID, "claude-deny")
    }

    func testCodexCommandQuickApproveUsesOrdinaryAcceptAndRejectUsesCancel() throws {
        let controller = CodexDesktopApprovalController()
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "command-quick",
                method: "item/commandExecution/requestApproval",
                params: [
                    "command": .string("swift test"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .string("acceptForSession"),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let quickActions = AIPluginQuickApprovalResolver.actions(for: try XCTUnwrap(surface))

        XCTAssertEqual(
            quickActions.approve,
            .codex(optionID: "codex-ipc-command-quick-option-0", action: .primary)
        )
        XCTAssertEqual(quickActions.reject, .codex(optionID: nil, action: .cancel))
    }

    func testCodexCommandQuickApproveIsUnavailableWithoutOrdinaryAccept() throws {
        let controller = CodexDesktopApprovalController()
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "command-session-only",
                method: "item/commandExecution/requestApproval",
                params: [
                    "command": .string("swift test"),
                    "availableDecisions": .array([
                        .string("acceptForSession"),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let quickActions = AIPluginQuickApprovalResolver.actions(for: try XCTUnwrap(surface))

        XCTAssertNil(quickActions.approve)
        XCTAssertEqual(quickActions.reject, .codex(optionID: nil, action: .cancel))
    }

    func testCodexUserInputDoesNotExposeQuickApprovalActions() throws {
        let controller = CodexDesktopApprovalController()
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "user-input-quick",
                method: "item/tool/requestUserInput",
                params: [
                    "questions": .array([
                        .object([
                            "id": .string("question-1"),
                            "question": .string("How should Codex adjust?"),
                            "options": .array([
                                .object(["label": .string("Proceed as-is")]),
                            ]),
                        ]),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let quickActions = AIPluginQuickApprovalResolver.actions(for: try XCTUnwrap(surface))

        XCTAssertNil(quickActions.approve)
        XCTAssertNil(quickActions.reject)
        XCTAssertFalse(quickActions.shouldRender)
    }

    func testCodexLegacyExecQuickRejectUsesDeniedOptionInsteadOfAbortCancel() throws {
        let controller = CodexDesktopApprovalController()
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "legacy-exec-quick",
                method: "execCommandApproval",
                params: [
                    "command": .array([.string("swift"), .string("test")]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let quickActions = AIPluginQuickApprovalResolver.actions(for: try XCTUnwrap(surface))

        XCTAssertEqual(
            quickActions.approve,
            .codex(optionID: "codex-ipc-legacy-exec-quick-option-0", action: .primary)
        )
        XCTAssertEqual(
            quickActions.reject,
            .codex(optionID: "codex-ipc-legacy-exec-quick-option-3", action: .primary)
        )
    }

    private func makeClaudeApproval(
        requestID: String,
        actions: [ApprovalAction]
    ) -> PendingApproval {
        PendingApproval(
            requestID: requestID,
            sessionID: "\(requestID)-session",
            host: .claude,
            approvalKind: .toolRequest,
            payload: ApprovalPayload(
                title: "Approval",
                toolName: "Bash",
                previewText: "swift test",
                command: "swift test",
                toolKind: .bash
            ),
            capabilities: .none,
            availableActions: actions,
            status: .pending
        )
    }
}

private extension AIPluginQuickApprovalAction {
    var claudeActionID: String? {
        guard case let .claude(action) = self else {
            return nil
        }
        return action.id
    }
}
