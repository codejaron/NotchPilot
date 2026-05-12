import XCTest
@testable import NotchPilotKit

final class AIPluginModelsTests: XCTestCase {
    func testExpandedSessionSummaryOnlyDimsCompletedSessions() {
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

        XCTAssertFalse(working.isDimmed)
        XCTAssertTrue(completed.isDimmed)
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
}
