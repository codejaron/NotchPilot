import XCTest
@testable import NotchPilotKit

final class CodexDesktopApprovalRequestRouterTests: XCTestCase {
    func testCanHandleAcceptsOnlyMCPToolApprovalElicitationsForMCPMethod() {
        let approvalRequest = CodexDesktopIPCRequestFrame(
            requestID: "mcp-approval",
            method: "mcpServer/elicitation/request",
            params: [
                "_meta": .object([
                    "codex_approval_kind": .string("mcp_tool_call"),
                ]),
            ],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let plainRequest = CodexDesktopIPCRequestFrame(
            requestID: "mcp-plain",
            method: "mcpServer/elicitation/request",
            params: [
                "_meta": .object([
                    "codex_approval_kind": .string("other"),
                ]),
            ],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )

        XCTAssertTrue(CodexDesktopApprovalRequestRouter.canHandle(approvalRequest))
        XCTAssertFalse(CodexDesktopApprovalRequestRouter.canHandle(plainRequest))
    }

    func testLiveDeliveryRequiresCurrentApprovalMethodThreadIDAndOwnerClient() {
        let liveRequest = CodexDesktopIPCRequestFrame(
            requestID: "command-live",
            method: "item/commandExecution/requestApproval",
            params: [
                "threadId": .string("thread-1"),
            ],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 3
        )
        let legacyRequest = CodexDesktopIPCRequestFrame(
            requestID: "legacy-live",
            method: "execCommandApproval",
            params: [
                "threadId": .string("thread-1"),
            ],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 3
        )
        let missingThreadRequest = CodexDesktopIPCRequestFrame(
            requestID: "command-no-thread",
            method: "item/commandExecution/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 3
        )

        XCTAssertEqual(
            CodexDesktopApprovalRequestRouter.liveDelivery(for: liveRequest),
            .threadFollower(ownerClientID: "desktop-client", conversationID: "thread-1", version: 1)
        )
        XCTAssertNil(CodexDesktopApprovalRequestRouter.liveDelivery(for: legacyRequest))
        XCTAssertNil(CodexDesktopApprovalRequestRouter.liveDelivery(for: missingThreadRequest))
    }
}
