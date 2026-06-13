import XCTest
@testable import NotchPilotKit

final class SneakPeekQueueTests: XCTestCase {
    func testQueuePrefersLowerPriorityAndPreservesFIFOForTies() {
        let queue = SneakPeekQueue()
        let highFirst = makeRequest(priority: 100)
        let highSecond = makeRequest(priority: 100)
        let low = makeRequest(priority: 0)

        queue.enqueue(highFirst)
        queue.enqueue(highSecond)
        queue.enqueue(low)

        XCTAssertEqual(queue.current?.id, low.id)

        _ = queue.dismissCurrent()
        XCTAssertEqual(queue.current?.id, highFirst.id)

        _ = queue.dismissCurrent()
        XCTAssertEqual(queue.current?.id, highSecond.id)
    }

    func testExpiringCurrentRequestPromotesTheNextRequest() {
        let queue = SneakPeekQueue()
        let first = makeRequest(priority: 0)
        let next = makeRequest(priority: 100)

        queue.enqueue(first)
        queue.enqueue(next)

        XCTAssertEqual(queue.expire(first.id)?.id, first.id)
        XCTAssertEqual(queue.current?.id, next.id)
    }

    func testExpiredAutoDismissRequestIsNotReturnedAsCurrent() {
        let queue = SneakPeekQueue()
        let expired = SneakPeekRequest(
            id: UUID(),
            pluginID: "media",
            priority: 0,
            target: .activeScreen,
            isInteractive: false,
            autoDismissAfter: 1,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let persistent = makeRequest(priority: 100)

        queue.enqueue(expired)
        queue.enqueue(persistent)

        XCTAssertEqual(queue.current(at: Date(timeIntervalSince1970: 2))?.id, persistent.id)
        XCTAssertEqual(queue.requests(at: Date(timeIntervalSince1970: 2)).map(\.id), [persistent.id])
    }

    func testPriorityRanksApprovalsAIActivityAndMediaPlayback() {
        // Lower priority value = served earlier in the queue.
        XCTAssertEqual(SneakPeekRequestPriority.ai, SneakPeekRequestPriority.aiApproval)
        XCTAssertLessThan(SneakPeekRequestPriority.aiApproval, SneakPeekRequestPriority.aiActivity)
        XCTAssertLessThan(SneakPeekRequestPriority.aiActivity, SneakPeekRequestPriority.mediaPlayback)
    }

    func testPriorityRanksSystemAlertBetweenAIApprovalAndAIActivity() {
        XCTAssertLessThan(SneakPeekRequestPriority.aiApproval, SneakPeekRequestPriority.systemMonitorAlert)
        XCTAssertLessThan(SneakPeekRequestPriority.systemMonitorAlert, SneakPeekRequestPriority.aiActivity)
        XCTAssertLessThan(SneakPeekRequestPriority.aiActivity, SneakPeekRequestPriority.mediaPlayback)
        XCTAssertLessThan(SneakPeekRequestPriority.mediaPlayback, SneakPeekRequestPriority.systemMonitor)
    }

    func testUpdatingPriorityKeepsRequestIdentityAndReordersQueue() {
        let queue = SneakPeekQueue()
        let normalSystem = makeRequest(priority: SneakPeekRequestPriority.systemMonitor)
        let aiActivity = makeRequest(priority: SneakPeekRequestPriority.aiActivity)

        queue.enqueue(normalSystem)
        queue.enqueue(aiActivity)

        let updated = queue.updatePriority(
            requestID: normalSystem.id,
            priority: SneakPeekRequestPriority.systemMonitorAlert
        )

        XCTAssertEqual(updated?.id, normalSystem.id)
        XCTAssertEqual(queue.current?.id, normalSystem.id)
        XCTAssertEqual(queue.current?.priority, SneakPeekRequestPriority.systemMonitorAlert)
    }

    func testAIPriorityResolvesApprovalAndActivityKindsSeparately() {
        XCTAssertEqual(SneakPeekRequestPriority.ai(for: .attention), SneakPeekRequestPriority.aiApproval)
        XCTAssertEqual(SneakPeekRequestPriority.ai(for: .activity), SneakPeekRequestPriority.aiActivity)
    }

    private func makeRequest(priority: Int) -> SneakPeekRequest {
        SneakPeekRequest(
            id: UUID(),
            pluginID: "ai",
            priority: priority,
            target: .activeScreen,
            isInteractive: false,
            autoDismissAfter: nil,
            createdAt: Date()
        )
    }
}
