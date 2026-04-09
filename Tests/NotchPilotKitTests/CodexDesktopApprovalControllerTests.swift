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
                "No, continue without running it",
            ]
        )
        XCTAssertEqual(surface?.threadID, "thread-1")
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

        XCTAssertEqual(updatedSurface?.options.map(\.isSelected), [false, true, false])
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
}
