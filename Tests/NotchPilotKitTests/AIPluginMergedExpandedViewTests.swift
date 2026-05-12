import SwiftUI
import XCTest
@testable import NotchPilotKit

@MainActor
final class AIPluginMergedExpandedViewTests: XCTestCase {
    func testCombinedSummariesMergesAcrossPluginsAndPrioritizesAttention() {
        let claudeAttention = makeSummary(
            id: "claude-attention",
            host: .claude,
            phase: .completed,
            approvalRequestID: "approval-1",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let codexWorking = makeSummary(
            id: "codex-working",
            host: .codex,
            phase: .working,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let plugins: [any AIPluginRendering] = [
            MergedViewProbeAIPlugin(id: "codex", summaries: [codexWorking]),
            MergedViewProbeAIPlugin(id: "claude", summaries: [claudeAttention]),
        ]

        let summaries = AIPluginMergedExpandedView.combinedSummaries(from: plugins)

        XCTAssertEqual(summaries.map(\.id), ["claude-attention", "codex-working"])
    }

    func testCombinedSummariesSortsByAttentionThenPhaseThenUpdatedAt() {
        let completedNewer = makeSummary(
            id: "completed-newer",
            host: .claude,
            phase: .completed,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let workingOlder = makeSummary(
            id: "working-older",
            host: .codex,
            phase: .working,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let workingNewer = makeSummary(
            id: "working-newer",
            host: .claude,
            phase: .working,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let plugins: [any AIPluginRendering] = [
            MergedViewProbeAIPlugin(id: "claude", summaries: [completedNewer, workingNewer]),
            MergedViewProbeAIPlugin(id: "codex", summaries: [workingOlder]),
        ]

        let summaries = AIPluginMergedExpandedView.combinedSummaries(from: plugins)

        XCTAssertEqual(summaries.map(\.id), ["working-newer", "working-older", "completed-newer"])
    }

    func testActivateSessionRoutesToClaudePluginForClaudeHost() {
        let claude = MergedViewProbeAIPlugin(id: "claude")
        let codex = MergedViewProbeAIPlugin(id: "codex")
        let summary = makeSummary(id: "claude-thread", host: .claude)

        let didActivate = AIPluginMergedExpandedView.activate(summary: summary, in: [codex, claude])

        XCTAssertTrue(didActivate)
        XCTAssertEqual(claude.activatedSessionIDs, ["claude-thread"])
        XCTAssertEqual(codex.activatedSessionIDs, [])
    }

    func testActivateSessionRoutesToClaudePluginForDevinHost() {
        let claude = MergedViewProbeAIPlugin(id: "claude")
        let summary = makeSummary(id: "devin-thread", host: .devin)

        let didActivate = AIPluginMergedExpandedView.activate(summary: summary, in: [claude])

        XCTAssertTrue(didActivate)
        XCTAssertEqual(claude.activatedSessionIDs, ["devin-thread"])
    }

    func testActivateSessionRoutesToCodexPluginForCodexHost() {
        let claude = MergedViewProbeAIPlugin(id: "claude")
        let codex = MergedViewProbeAIPlugin(id: "codex")
        let summary = makeSummary(id: "codex-thread", host: .codex)

        let didActivate = AIPluginMergedExpandedView.activate(summary: summary, in: [claude, codex])

        XCTAssertTrue(didActivate)
        XCTAssertEqual(codex.activatedSessionIDs, ["codex-thread"])
        XCTAssertEqual(claude.activatedSessionIDs, [])
    }

    func testRespondRoutesApprovalToCorrectPlugin() {
        let claude = MergedViewProbeAIPlugin(id: "claude")
        let codex = MergedViewProbeAIPlugin(id: "codex")
        let approval = makeApproval(requestID: "codex-approval", host: .codex)
        let action = ApprovalAction(
            id: "allow",
            title: "Allow",
            style: .primary,
            payload: .claude(.allowOnce)
        )

        AIPluginMergedExpandedView.respond(to: approval, with: action, in: [claude, codex])

        XCTAssertEqual(codex.respondedApprovals.map(\.requestID), ["codex-approval"])
        XCTAssertEqual(codex.respondedApprovals.map(\.action), [action])
        XCTAssertEqual(claude.respondedApprovals.map(\.requestID), [])
    }
}

@MainActor
private final class MergedViewProbeAIPlugin: AIPluginRendering {
    let id: String
    let title: String
    let iconSystemName = "sparkles"
    let accentColor = Color.blue
    var isEnabled = true
    let dockOrder: Int
    var sessions: [AISession]
    var pendingApprovals: [PendingApproval]
    var codexActionableSurface: CodexActionableSurface?
    var currentCompactActivity: AIPluginCompactActivity?
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary]
    private(set) var activatedSessionIDs: [String] = []
    private(set) var respondedApprovals: [(requestID: String, action: ApprovalAction)] = []

    init(
        id: String,
        dockOrder: Int = 100,
        summaries: [AIPluginExpandedSessionSummary] = [],
        pendingApprovals: [PendingApproval] = []
    ) {
        self.id = id
        self.title = id
        self.dockOrder = dockOrder
        self.sessions = []
        self.pendingApprovals = pendingApprovals
        self.expandedSessionSummaries = summaries
    }

    func displayTitle(for session: AISession) -> String? {
        session.sessionTitle
    }

    @discardableResult
    func activateSession(id: String) -> Bool {
        activatedSessionIDs.append(id)
        return true
    }

    func respond(to requestID: String, with action: ApprovalAction) {
        respondedApprovals.append((requestID, action))
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}

private func makeSummary(
    id: String,
    host: AIHost,
    phase: AIPluginSessionPhase = .working,
    approvalRequestID: String? = nil,
    codexSurfaceID: String? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 0)
) -> AIPluginExpandedSessionSummary {
    AIPluginExpandedSessionSummary(
        id: id,
        host: host,
        title: id,
        subtitle: "Testing",
        phase: phase,
        approvalCount: approvalRequestID == nil ? 0 : 1,
        approvalRequestID: approvalRequestID,
        codexSurfaceID: codexSurfaceID,
        updatedAt: updatedAt,
        inputTokenCount: nil,
        outputTokenCount: nil
    )
}

private func makeApproval(requestID: String, host: AIHost) -> PendingApproval {
    PendingApproval(
        requestID: requestID,
        sessionID: "\(requestID)-session",
        host: host,
        approvalKind: .toolRequest,
        payload: ApprovalPayload(
            title: "Approval",
            toolName: "Bash",
            previewText: "echo hello",
            command: "echo hello",
            toolKind: .bash
        ),
        capabilities: .none,
        availableActions: [],
        status: .pending
    )
}
