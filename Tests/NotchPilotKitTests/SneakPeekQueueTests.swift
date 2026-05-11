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

    func testNotificationsPriorityRanksBetweenAIAndMediaPlayback() {
        // Lower priority value = served earlier in the queue.
        XCTAssertLessThan(SneakPeekRequestPriority.ai, SneakPeekRequestPriority.notifications)
        XCTAssertLessThan(SneakPeekRequestPriority.notifications, SneakPeekRequestPriority.mediaPlayback)
        XCTAssertEqual(SneakPeekRequestPriority.notifications, 500)
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
