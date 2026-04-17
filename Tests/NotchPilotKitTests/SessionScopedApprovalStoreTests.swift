import XCTest
@testable import NotchPilotKit

final class SessionScopedApprovalStoreTests: XCTestCase {
    func testToolRuleMatchesSameToolInSameSession() {
        let store = SessionScopedApprovalStore()
        store.addRule(.tool("Edit"), sessionID: "sess-1")

        let payload = makePayload(toolName: "Edit", toolKind: .edit)
        XCTAssertTrue(store.matches(sessionID: "sess-1", payload: payload))
    }

    func testToolRuleDoesNotMatchDifferentSession() {
        let store = SessionScopedApprovalStore()
        store.addRule(.tool("Edit"), sessionID: "sess-1")

        let payload = makePayload(toolName: "Edit", toolKind: .edit)
        XCTAssertFalse(store.matches(sessionID: "sess-2", payload: payload))
    }

    func testEditToolRuleMatchesEveryEditToolKindInSameSession() {
        let store = SessionScopedApprovalStore()
        store.addRule(.tool("Edit"), sessionID: "sess-1")

        XCTAssertTrue(store.matches(sessionID: "sess-1", payload: makePayload(toolName: "Write", toolKind: .edit)))
        XCTAssertTrue(store.matches(sessionID: "sess-1", payload: makePayload(toolName: "MultiEdit", toolKind: .edit)))
        XCTAssertTrue(store.matches(sessionID: "sess-1", payload: makePayload(toolName: "NotebookEdit", toolKind: .edit)))
    }

    func testToolRuleDoesNotMatchDifferentTool() {
        let store = SessionScopedApprovalStore()
        store.addRule(.tool("Edit"), sessionID: "sess-1")

        let payload = makePayload(toolName: "Bash", toolKind: .bash)
        XCTAssertFalse(store.matches(sessionID: "sess-1", payload: payload))
    }

    func testBashPrefixRuleMatchesSamePrefix() {
        let store = SessionScopedApprovalStore()
        store.addRule(.bashPrefix("git status"), sessionID: "sess-1")

        let payload = makePayload(
            toolName: "Bash",
            toolKind: .bash,
            bashCommandPrefix: "git status"
        )
        XCTAssertTrue(store.matches(sessionID: "sess-1", payload: payload))
    }

    func testWebFetchDomainRuleMatchesSameDomain() {
        let store = SessionScopedApprovalStore()
        store.addRule(.webFetchDomain("example.com"), sessionID: "sess-1")

        let payload = makePayload(
            toolName: "WebFetch",
            toolKind: .webFetch,
            webFetchDomain: "example.com"
        )
        XCTAssertTrue(store.matches(sessionID: "sess-1", payload: payload))
    }

    func testMCPRuleMatchesSameServerAndTool() {
        let store = SessionScopedApprovalStore()
        store.addRule(.mcp(server: "linear", tool: "create_issue"), sessionID: "sess-1")

        let payload = makePayload(
            toolName: "mcp__linear__create_issue",
            toolKind: .mcp,
            mcpServer: "linear",
            mcpTool: "create_issue"
        )
        XCTAssertTrue(store.matches(sessionID: "sess-1", payload: payload))
    }

    func testClearSessionRemovesAllRules() {
        let store = SessionScopedApprovalStore()
        store.addRule(.tool("Edit"), sessionID: "sess-1")
        store.addRule(.bashPrefix("git status"), sessionID: "sess-1")
        store.clearSession("sess-1")

        let editPayload = makePayload(toolName: "Edit", toolKind: .edit)
        XCTAssertFalse(store.matches(sessionID: "sess-1", payload: editPayload))
        XCTAssertTrue(store.rules(for: "sess-1").isEmpty)
    }

    func testClearSessionDoesNotAffectOtherSessions() {
        let store = SessionScopedApprovalStore()
        store.addRule(.tool("Edit"), sessionID: "sess-1")
        store.addRule(.tool("Edit"), sessionID: "sess-2")
        store.clearSession("sess-1")

        let payload = makePayload(toolName: "Edit", toolKind: .edit)
        XCTAssertFalse(store.matches(sessionID: "sess-1", payload: payload))
        XCTAssertTrue(store.matches(sessionID: "sess-2", payload: payload))
    }

    func testAddRuleIsIdempotent() {
        let store = SessionScopedApprovalStore()
        store.addRule(.tool("Edit"), sessionID: "sess-1")
        store.addRule(.tool("Edit"), sessionID: "sess-1")
        store.addRule(.tool("Edit"), sessionID: "sess-1")

        XCTAssertEqual(store.rules(for: "sess-1").count, 1)
    }

    private func makePayload(
        toolName: String,
        toolKind: ClaudeToolKind,
        bashCommandPrefix: String? = nil,
        webFetchDomain: String? = nil,
        mcpServer: String? = nil,
        mcpTool: String? = nil
    ) -> ApprovalPayload {
        ApprovalPayload(
            title: "\(toolName) wants approval",
            toolName: toolName,
            previewText: "preview",
            toolKind: toolKind,
            bashCommandPrefix: bashCommandPrefix,
            webFetchDomain: webFetchDomain,
            mcpServer: mcpServer,
            mcpTool: mcpTool
        )
    }
}
