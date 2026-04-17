import XCTest
@testable import NotchPilotKit

final class ApprovalActionTests: XCTestCase {
    func testEditSessionActionUsesSharedEditRule() throws {
        let actions = ApprovalAction.claudeActions(
            toolKind: .edit,
            toolName: "Write",
            bashCommandPrefix: nil,
            webFetchDomain: nil,
            mcpServer: nil,
            mcpTool: nil
        )

        let action = try XCTUnwrap(actions.first(where: { $0.id == "claude-allow-persist" }))
        guard case let .claude(decision) = action.payload else {
            return XCTFail("expected Claude decision")
        }

        XCTAssertEqual(decision.sessionRule, .tool("Edit"))
        XCTAssertNil(decision.persistRule)
    }
}
