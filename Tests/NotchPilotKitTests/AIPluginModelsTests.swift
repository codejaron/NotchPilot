import XCTest
@testable import NotchPilotKit

final class AIPluginModelsTests: XCTestCase {
    func testExpandedSessionSummaryDimsTerminalSessions() {
        let working = AIPluginExpandedSessionSummary(
            id: "thread-working",
            host: .claude,
            title: "Working",
            subtitle: "Processing",
            phase: .working,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            inputTokenCount: nil,
            outputTokenCount: nil
        )
        let completed = AIPluginExpandedSessionSummary(
            id: "thread-completed",
            host: .claude,
            title: "Completed",
            subtitle: "Done",
            phase: .completed,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 1),
            inputTokenCount: nil,
            outputTokenCount: nil
        )
        let interrupted = AIPluginExpandedSessionSummary(
            id: "thread-interrupted",
            host: .codex,
            title: "Stopped",
            subtitle: "Stopped",
            phase: .interrupted,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 2),
            inputTokenCount: nil,
            outputTokenCount: nil
        )

        XCTAssertFalse(working.isDimmed)
        XCTAssertTrue(working.canStopManually)
        XCTAssertTrue(completed.isDimmed)
        XCTAssertFalse(completed.canStopManually)
        XCTAssertTrue(interrupted.isDimmed)
        XCTAssertFalse(interrupted.canStopManually)
    }

    func testSessionRowsOnlyUsePrimaryAreaForAttentionAndAlwaysExposeJumpTarget() {
        let attention = AIPluginExpandedSessionSummary(
            id: "thread-attention",
            host: .claude,
            title: "Needs approval",
            subtitle: "Bash",
            phase: .working,
            approvalCount: 1,
            approvalRequestID: "approval-1",
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            inputTokenCount: nil,
            outputTokenCount: nil
        )
        let ordinary = AIPluginExpandedSessionSummary(
            id: "thread-ordinary",
            host: .claude,
            title: "Working",
            subtitle: "Processing",
            phase: .working,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 1),
            inputTokenCount: nil,
            outputTokenCount: nil
        )

        XCTAssertEqual(attention.primaryRowAction, .reviewAttention)
        XCTAssertGreaterThanOrEqual(attention.jumpAccessoryHitWidth, 36)
        XCTAssertEqual(ordinary.primaryRowAction, .none)
        XCTAssertGreaterThanOrEqual(ordinary.jumpAccessoryHitWidth, 36)
    }

    func testJumpAccessoryStaysVisibleWhenSessionRowIsDimmed() {
        let presentation = AIPluginSessionJumpAccessoryPresentation(isRowDimmed: true)

        XCTAssertGreaterThanOrEqual(presentation.effectiveSymbolOpacity, 0.45)
        XCTAssertGreaterThan(presentation.backgroundOpacity, 0)
        XCTAssertGreaterThan(presentation.borderOpacity, 0)
    }

    func testExpandedSessionSummaryComputesContextUsagePercent() {
        let summary = AIPluginExpandedSessionSummary(
            id: "thread-context",
            host: .codex,
            title: "Context",
            subtitle: "Working",
            phase: .working,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            inputTokenCount: 20_000,
            outputTokenCount: 5_000,
            contextWindowTokenCount: 100_000
        )

        XCTAssertEqual(summary.contextUsagePercent, 25)
        XCTAssertTrue(summary.hasContextUsage)
        XCTAssertTrue(summary.hasMeta)
    }

    func testExpandedSessionSummaryUsesLastTokenUsageForTokenCountsAndContextUsagePercent() {
        let summary = AIPluginExpandedSessionSummary(
            id: "thread-context-last-usage",
            host: .codex,
            title: "Context",
            subtitle: "Working",
            phase: .working,
            approvalCount: 0,
            approvalRequestID: nil,
            codexSurfaceID: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            inputTokenCount: 69_000,
            outputTokenCount: 1_200,
            contextInputTokenCount: 69_000,
            contextWindowTokenCount: 258_400
        )

        XCTAssertEqual(summary.inputTokenCount, 69_000)
        XCTAssertEqual(summary.outputTokenCount, 1_200)
        XCTAssertEqual(try XCTUnwrap(summary.contextUsagePercent), 26.702, accuracy: 0.001)
    }
}
