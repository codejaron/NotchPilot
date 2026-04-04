import XCTest
@testable import NotchPilotKit

final class SneakPeekQueueTests: XCTestCase {
    func testQueuePrefersHigherPriorityAndPreservesFIFOForTies() {
        let queue = SneakPeekQueue()
        let lowFirst = makeRequest(priority: 100)
        let lowSecond = makeRequest(priority: 100)
        let high = makeRequest(priority: 1000)

        queue.enqueue(lowFirst)
        queue.enqueue(lowSecond)
        queue.enqueue(high)

        XCTAssertEqual(queue.current?.id, high.id)

        _ = queue.dismissCurrent()
        XCTAssertEqual(queue.current?.id, lowFirst.id)

        _ = queue.dismissCurrent()
        XCTAssertEqual(queue.current?.id, lowSecond.id)
    }

    func testExpiringCurrentRequestPromotesTheNextRequest() {
        let queue = SneakPeekQueue()
        let first = makeRequest(priority: 1000)
        let next = makeRequest(priority: 100)

        queue.enqueue(first)
        queue.enqueue(next)

        XCTAssertEqual(queue.expire(first.id)?.id, first.id)
        XCTAssertEqual(queue.current?.id, next.id)
    }

    private func makeRequest(priority: Int) -> SneakPeekRequest {
        SneakPeekRequest(
            id: UUID(),
            pluginID: "ai",
            priority: priority,
            target: .activeScreen,
            isInteractive: priority >= 1000,
            autoDismissAfter: priority >= 1000 ? nil : 3,
            createdAt: Date()
        )
    }
}
