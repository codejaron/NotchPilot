import XCTest
@testable import NotchPilotKit

final class CodexDesktopApprovalControllerTests: XCTestCase {
    func testCommandApprovalCreatesActionableSurfaceFromIPCRequest() {
        let controller = CodexDesktopApprovalController()
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "approval-1",
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("item-1"),
                    "reason": .string("Do you want to approve deleting this temporary file with rm -rf as requested?"),
                    "command": .string("rm -rf '/tmp/demo'"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .object([
                            "acceptWithExecpolicyAmendment": .object([
                                "execpolicy_amendment": .array([
                                    .string("rm -rf '/tmp/demo'")
                                ])
                            ])
                        ]),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        XCTAssertEqual(surface?.id, "codex-ipc-approval-1")
        XCTAssertEqual(
            surface?.summary,
            "Do you want to approve deleting this temporary file with rm -rf as requested?"
        )
        XCTAssertEqual(surface?.commandPreview, "rm -rf '/tmp/demo'")
        XCTAssertEqual(surface?.primaryButtonTitle, "Submit")
        XCTAssertEqual(surface?.cancelButtonTitle, "Skip")
        XCTAssertEqual(
            surface?.options.map(\.title),
            [
                "Yes",
                "Yes, and don't ask again for commands that start with `rm -rf '/tmp/demo'`",
            ]
        )
        XCTAssertEqual(surface?.textInput?.text, "")
        XCTAssertTrue(surface?.textInput?.isEditable ?? false)
        XCTAssertNil(surface?.textInput?.attachedOptionID)
        XCTAssertEqual(surface?.threadID, "thread-1")
    }

    func testCommandApprovalOptionTitleShowsRawShellWrappedCommandForShellWrappedExecpolicyAmendment() {
        let controller = CodexDesktopApprovalController()
        let command = "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotchLayoutMetricsTests|NotchWindowTests|ScreenSessionModelTests'"
        let rawCommand = #"/bin/zsh -lc "\#(command)""#
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "approval-shell-amendment",
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-1"),
                    "command": .string(rawCommand),
                    "availableDecisions": .array([
                        .string("accept"),
                        .object([
                            "acceptWithExecpolicyAmendment": .object([
                                "execpolicy_amendment": .array([
                                    .string("/bin/zsh"),
                                    .string("-lc"),
                                    .string(command),
                                ]),
                            ]),
                        ]),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        XCTAssertEqual(
            surface?.options.map(\.title),
            [
                "Yes",
                "Yes, and don't ask again for commands that start with `\(rawCommand)`",
            ]
        )
    }

    func testCommandApprovalOptionTitleFallsBackToRawCommandWhenExecpolicyAmendmentIsOnlyShellExecutable() {
        let controller = CodexDesktopApprovalController()
        let command = "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotchLayoutMetricsTests|NotchWindowTests|ScreenSessionModelTests'"
        let rawCommand = #"/bin/zsh -lc "\#(command)""#
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "approval-shell-only-amendment",
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-1"),
                    "command": .string(rawCommand),
                    "availableDecisions": .array([
                        .string("accept"),
                        .object([
                            "acceptWithExecpolicyAmendment": .object([
                                "execpolicy_amendment": .array([
                                    .string("/bin/zsh"),
                                ]),
                            ]),
                        ]),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        XCTAssertEqual(
            surface?.options.map(\.title),
            [
                "Yes",
                "Yes, and don't ask again for commands that start with `\(rawCommand)`",
            ]
        )
    }

    func testSubmittingSelectedCommandApprovalDecisionReturnsMatchingIPCResponseAndClearsSurface() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "approval-2",
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("item-1"),
                    "command": .string("rm -rf '/tmp/demo'"),
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

        let updatedSurface = controller.selectOption("codex-ipc-approval-2-option-1", on: "codex-ipc-approval-2")
        let response = controller.perform(action: .primary, on: "codex-ipc-approval-2")

        XCTAssertEqual(updatedSurface?.options.map(\.isSelected), [false, true])
        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "approval-2",
                method: "item/commandExecution/requestApproval",
                result: .object([
                    "decision": .string("acceptForSession"),
                ]),
                submission: .response
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testSubmittingTypedCommandApprovalFeedbackDeclinesAndBuildsSteerWithStartTurnFallback() {
        let controller = CodexDesktopApprovalController(
            followUpCreatedAtMillisecondsProvider: { 123 }
        )
        _ = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "approval-feedback-1",
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-feedback-1"),
                    "turnId": .string("turn-feedback-1"),
                    "itemId": .string("item-feedback-1"),
                    "command": .string("rm -rf '/tmp/demo'"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .object([
                            "acceptWithExecpolicyAmendment": .object([
                                "execpolicy_amendment": .array([
                                    .string("rm -rf '/tmp/demo'")
                                ])
                            ])
                        ]),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let updatedSurface = controller.updateText(
            "Use trash instead of rm -rf.",
            on: "codex-ipc-approval-feedback-1"
        )
        let response = controller.perform(action: .primary, on: "codex-ipc-approval-feedback-1")

        XCTAssertEqual(updatedSurface?.options.map(\.isSelected), [false, false])
        XCTAssertEqual(updatedSurface?.textInput?.text, "Use trash instead of rm -rf.")
        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "approval-feedback-1",
                method: "item/commandExecution/requestApproval",
                result: .object([
                    "decision": .string("decline"),
                ]),
                submission: .response,
                followUpSubmission: .request(
                    method: "thread-follower-steer-turn",
                    params: [
                        "conversationId": .string("thread-feedback-1"),
                        "input": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("Use trash instead of rm -rf."),
                                "text_elements": .array([]),
                            ]),
                        ]),
                        "attachments": .array([]),
                        "restoreMessage": .object([
                            "id": .string("approval-follow-up-approval-feedback-1"),
                            "text": .string("Use trash instead of rm -rf."),
                            "context": .object([
                                "prompt": .string("Use trash instead of rm -rf."),
                                "addedFiles": .array([]),
                                "collaborationMode": .null,
                                "ideContext": .null,
                                "imageAttachments": .array([]),
                                "fileAttachments": .array([]),
                                "commentAttachments": .array([]),
                                "pullRequestChecks": .array([]),
                                "reviewFindings": .array([]),
                                "priorConversation": .null,
                                "workspaceRoots": .array([]),
                            ]),
                            "cwd": .null,
                            "createdAt": .integer(123),
                        ]),
                    ],
                    targetClientID: "desktop-client",
                    version: 1
                ),
                fallbackFollowUpSubmission: .request(
                    method: "thread-follower-start-turn",
                    params: [
                        "conversationId": .string("thread-feedback-1"),
                        "turnStartParams": .object([
                            "input": .array([
                                .object([
                                    "type": .string("text"),
                                    "text": .string("Use trash instead of rm -rf."),
                                    "text_elements": .array([]),
                                ]),
                            ]),
                            "cwd": .null,
                            "model": .null,
                            "effort": .null,
                            "approvalPolicy": .null,
                            "approvalsReviewer": .string("user"),
                            "sandboxPolicy": .null,
                            "attachments": .array([]),
                            "collaborationMode": .null,
                        ]),
                    ],
                    targetClientID: "desktop-client",
                    version: 1
                ),
                followUpConversationID: "thread-feedback-1"
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testCancellingCurrentApprovalRespondsWithCancelDecision() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "approval-3",
                method: "item/fileChange/requestApproval",
                params: [
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("item-1"),
                    "reason": .string("Would you like to make the following edits?"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let response = controller.perform(action: .cancel, on: "codex-ipc-approval-3")

        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "approval-3",
                method: "item/fileChange/requestApproval",
                result: .object([
                    "decision": .string("decline"),
                ]),
                submission: .response
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testCancellingCommandApprovalPrefersDeclineWhenAvailable() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "approval-4",
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                    "itemId": .string("item-1"),
                    "command": .string("rm -rf '/tmp/demo'"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .string("decline"),
                        .string("cancel"),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let response = controller.perform(action: .cancel, on: "codex-ipc-approval-4")

        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "approval-4",
                method: "item/commandExecution/requestApproval",
                result: .object([
                    "decision": .string("decline"),
                ]),
                submission: .response
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testLegacyExecCommandApprovalCreatesActionableSurfaceFromIPCRequest() {
        let controller = CodexDesktopApprovalController()
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "legacy-approval-1",
                method: "execCommandApproval",
                params: [
                    "conversationId": .string("thread-legacy"),
                    "callId": .string("call-1"),
                    "approvalId": .string("approval-callback-1"),
                    "command": .array([
                        .string("rm"),
                        .string("-rf"),
                        .string("/tmp/demo"),
                    ]),
                    "cwd": .string("/Users/jaron/data/project/NotchPilot"),
                    "reason": .string("Do you want to approve deleting this temporary file with rm -rf as requested?"),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        XCTAssertEqual(surface?.id, "codex-ipc-legacy-approval-1")
        XCTAssertEqual(
            surface?.summary,
            "Do you want to approve deleting this temporary file with rm -rf as requested?"
        )
        XCTAssertEqual(surface?.commandPreview, "rm -rf /tmp/demo")
        XCTAssertEqual(surface?.threadID, "thread-legacy")
        XCTAssertEqual(
            surface?.options.map(\.title),
            [
                "Yes",
                "Yes, and don't ask again for commands that start with `rm -rf /tmp/demo`",
                "Yes, and don't ask again for this command in this session",
                "No, continue without running it",
            ]
        )
    }

    func testLegacyExecCommandApprovalPrimaryActionReturnsLegacyApprovedForSessionDecision() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "legacy-approval-2",
                method: "execCommandApproval",
                params: [
                    "conversationId": .string("thread-legacy"),
                    "callId": .string("call-2"),
                    "command": .array([
                        .string("rm"),
                        .string("-rf"),
                        .string("/tmp/demo"),
                    ]),
                    "cwd": .string("/Users/jaron/data/project/NotchPilot"),
                    "reason": .string("Would you like to run the following command?"),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let updatedSurface = controller.selectOption("codex-ipc-legacy-approval-2-option-2", on: "codex-ipc-legacy-approval-2")
        let response = controller.perform(action: .primary, on: "codex-ipc-legacy-approval-2")

        XCTAssertEqual(updatedSurface?.options.map(\.isSelected), [false, false, true, false])
        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "legacy-approval-2",
                method: "execCommandApproval",
                result: .object([
                    "decision": .string("approved_for_session"),
                ]),
                submission: .response
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testSubmittingLiveCommandApprovalBuildsThreadFollowerDecisionRequest() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handleLiveRequest(
            CodexDesktopIPCRequestFrame(
                requestID: "66",
                rawRequestID: .integer(66),
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-live-1"),
                    "command": .string("rm -rf '/tmp/demo'"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-owner-client",
                targetClientID: nil,
                version: nil
            )
        )

        let response = controller.perform(action: .primary, on: "codex-ipc-66")

        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "66",
                method: "item/commandExecution/requestApproval",
                result: .object([
                    "decision": .string("accept"),
                ]),
                submission: .request(
                    method: "thread-follower-command-approval-decision",
                    params: [
                        "conversationId": .string("thread-live-1"),
                        "requestId": .integer(66),
                        "decision": .string("accept"),
                    ],
                    targetClientID: "desktop-owner-client",
                    version: 1
                )
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testSubmittingLiveCommandApprovalFeedbackBuildsDeclineAndThreadFollowerSteerRequestWithStartTurnFallback() {
        let controller = CodexDesktopApprovalController(
            followUpCreatedAtMillisecondsProvider: { 123 }
        )
        _ = controller.handleLiveRequest(
            CodexDesktopIPCRequestFrame(
                requestID: "67",
                rawRequestID: .integer(67),
                method: "item/commandExecution/requestApproval",
                params: [
                    "threadId": .string("thread-live-feedback-1"),
                    "turnId": .string("turn-live-feedback-1"),
                    "command": .string("rm -rf '/tmp/demo'"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-owner-client",
                targetClientID: nil,
                version: nil
            )
        )
        _ = controller.updateText("Use trash instead.", on: "codex-ipc-67")

        let response = controller.perform(action: .primary, on: "codex-ipc-67")

        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "67",
                method: "item/commandExecution/requestApproval",
                result: .object([
                    "decision": .string("decline"),
                ]),
                submission: .request(
                    method: "thread-follower-command-approval-decision",
                    params: [
                        "conversationId": .string("thread-live-feedback-1"),
                        "requestId": .integer(67),
                        "decision": .string("decline"),
                    ],
                    targetClientID: "desktop-owner-client",
                    version: 1
                ),
                followUpSubmission: .request(
                    method: "thread-follower-steer-turn",
                    params: [
                        "conversationId": .string("thread-live-feedback-1"),
                        "input": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("Use trash instead."),
                                "text_elements": .array([]),
                            ]),
                        ]),
                        "attachments": .array([]),
                        "restoreMessage": .object([
                            "id": .string("approval-follow-up-67"),
                            "text": .string("Use trash instead."),
                            "context": .object([
                                "prompt": .string("Use trash instead."),
                                "addedFiles": .array([]),
                                "collaborationMode": .null,
                                "ideContext": .null,
                                "imageAttachments": .array([]),
                                "fileAttachments": .array([]),
                                "commentAttachments": .array([]),
                                "pullRequestChecks": .array([]),
                                "reviewFindings": .array([]),
                                "priorConversation": .null,
                                "workspaceRoots": .array([]),
                            ]),
                            "cwd": .null,
                            "createdAt": .integer(123),
                        ]),
                    ],
                    targetClientID: "desktop-owner-client",
                    version: 1
                ),
                fallbackFollowUpSubmission: .request(
                    method: "thread-follower-start-turn",
                    params: [
                        "conversationId": .string("thread-live-feedback-1"),
                        "turnStartParams": .object([
                            "input": .array([
                                .object([
                                    "type": .string("text"),
                                    "text": .string("Use trash instead."),
                                    "text_elements": .array([]),
                                ]),
                            ]),
                            "cwd": .null,
                            "model": .null,
                            "effort": .null,
                            "approvalPolicy": .null,
                            "approvalsReviewer": .string("user"),
                            "sandboxPolicy": .null,
                            "attachments": .array([]),
                            "collaborationMode": .null,
                        ]),
                    ],
                    targetClientID: "desktop-owner-client",
                    version: 1
                ),
                followUpConversationID: "thread-live-feedback-1"
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testSubmittingLiveFileApprovalBuildsThreadFollowerDecisionRequest() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handleLiveRequest(
            CodexDesktopIPCRequestFrame(
                requestID: "11",
                rawRequestID: .integer(11),
                method: "item/fileChange/requestApproval",
                params: [
                    "threadId": .string("thread-live-file-1"),
                    "grantRoot": .string("/tmp/demo"),
                    "availableDecisions": .array([
                        .string("accept"),
                        .string("decline"),
                    ]),
                ],
                sourceClientID: "desktop-owner-client",
                targetClientID: nil,
                version: nil
            )
        )

        let response = controller.perform(action: .primary, on: "codex-ipc-11")

        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "11",
                method: "item/fileChange/requestApproval",
                result: .object([
                    "decision": .string("accept"),
                ]),
                submission: .request(
                    method: "thread-follower-file-approval-decision",
                    params: [
                        "conversationId": .string("thread-live-file-1"),
                        "requestId": .integer(11),
                        "decision": .string("accept"),
                    ],
                    targetClientID: "desktop-owner-client",
                    version: 1
                )
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testUserInputRequestCreatesStandaloneThirdRowSurfaceFromIPCRequest() {
        let controller = CodexDesktopApprovalController()
        let surface = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "user-input-1",
                method: "item/tool/requestUserInput",
                params: [
                    "threadId": .string("thread-user-input-1"),
                    "turnId": .string("turn-user-input-1"),
                    "itemId": .string("item-user-input-1"),
                    "questions": .array([
                        .object([
                            "id": .string("question-1"),
                            "question": .string("How should Codex adjust?"),
                            "isOther": .bool(true),
                            "options": .array([
                                .object([
                                    "label": .string("Proceed as-is"),
                                    "description": .string("Keep going without changes."),
                                ]),
                                .object([
                                    "label": .string("Ask again later"),
                                    "description": .string("Defer this choice."),
                                ]),
                            ]),
                        ]),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        XCTAssertEqual(surface?.id, "codex-ipc-user-input-1")
        XCTAssertEqual(surface?.summary, "How should Codex adjust?")
        XCTAssertNil(surface?.commandPreview)
        XCTAssertEqual(surface?.options.map(\.title), ["Proceed as-is", "Ask again later"])
        XCTAssertEqual(surface?.textInput?.text, "")
        XCTAssertTrue(surface?.textInput?.isEditable ?? false)
        XCTAssertNil(surface?.textInput?.attachedOptionID)
        XCTAssertEqual(surface?.threadID, "thread-user-input-1")
    }

    func testSubmittingTypedUserInputReturnsMatchingIPCResponseAndClearsSurface() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handle(
            request: CodexDesktopIPCRequestFrame(
                requestID: "user-input-2",
                method: "item/tool/requestUserInput",
                params: [
                    "threadId": .string("thread-user-input-2"),
                    "turnId": .string("turn-user-input-2"),
                    "itemId": .string("item-user-input-2"),
                    "questions": .array([
                        .object([
                            "id": .string("question-2"),
                            "question": .string("How should Codex adjust?"),
                            "isOther": .bool(true),
                            "options": .array([
                                .object([
                                    "label": .string("Proceed as-is"),
                                    "description": .string("Keep going."),
                                ]),
                                .object([
                                    "label": .string("Ask again later"),
                                    "description": .string("Defer this choice."),
                                ]),
                            ]),
                        ]),
                    ]),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let updatedSurface = controller.updateText("Use a safer deletion flow.", on: "codex-ipc-user-input-2")
        let response = controller.perform(action: .primary, on: "codex-ipc-user-input-2")

        XCTAssertEqual(updatedSurface?.options.map(\.isSelected), [false, false])
        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "user-input-2",
                method: "item/tool/requestUserInput",
                result: .object([
                    "answers": .object([
                        "question-2": .object([
                            "answers": .array([
                                .string("Use a safer deletion flow."),
                            ]),
                        ]),
                    ]),
                ]),
                submission: .response
            )
        )
        XCTAssertNil(controller.currentSurface)
    }

    func testSubmittingLiveUserInputBuildsThreadFollowerSubmitRequest() {
        let controller = CodexDesktopApprovalController()
        _ = controller.handleLiveRequest(
            CodexDesktopIPCRequestFrame(
                requestID: "88",
                rawRequestID: .integer(88),
                method: "item/tool/requestUserInput",
                params: [
                    "threadId": .string("thread-live-user-input-1"),
                    "turnId": .string("turn-live-user-input-1"),
                    "itemId": .string("item-live-user-input-1"),
                    "questions": .array([
                        .object([
                            "id": .string("question-live-1"),
                            "question": .string("How should Codex adjust?"),
                            "isOther": .bool(true),
                            "options": .array([
                                .object([
                                    "label": .string("Proceed as-is"),
                                    "description": .string("Keep going."),
                                ]),
                            ]),
                        ]),
                    ]),
                ],
                sourceClientID: "desktop-owner-client",
                targetClientID: nil,
                version: nil
            )
        )
        _ = controller.updateText("Do not delete the file.", on: "codex-ipc-88")

        let response = controller.perform(action: .primary, on: "codex-ipc-88")

        XCTAssertEqual(
            response,
            CodexDesktopApprovalResponse(
                requestID: "88",
                method: "item/tool/requestUserInput",
                result: .object([
                    "answers": .object([
                        "question-live-1": .object([
                            "answers": .array([
                                .string("Do not delete the file."),
                            ]),
                        ]),
                    ]),
                ]),
                submission: .request(
                    method: "thread-follower-submit-user-input",
                    params: [
                        "conversationId": .string("thread-live-user-input-1"),
                        "requestId": .integer(88),
                        "response": .object([
                            "answers": .object([
                                "question-live-1": .object([
                                    "answers": .array([
                                        .string("Do not delete the file."),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    targetClientID: "desktop-owner-client",
                    version: 1
                )
            )
        )
        XCTAssertNil(controller.currentSurface)
    }
}
