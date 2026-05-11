import XCTest
@testable import NotchPilotKit

final class NotificationHistoryStoreTests: XCTestCase {
    private func makeNotification(id: UUID = UUID(), recID: Int64, bundleID: String, deliveredAt: Date) -> SystemNotification {
        SystemNotification(
            id: id, dbRecordID: recID,
            bundleIdentifier: bundleID,
            appDisplayName: bundleID,
            title: "T", subtitle: nil, body: "B",
            deliveredAt: deliveredAt
        )
    }

    @MainActor
    func testAppendsAndPreservesNewestFirst() {
        let store = NotificationHistoryStore(limit: 100)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        store.append(makeNotification(recID: 1, bundleID: "a", deliveredAt: t0), muted: false)
        store.append(makeNotification(recID: 2, bundleID: "a", deliveredAt: t0.addingTimeInterval(10)), muted: false)

        XCTAssertEqual(store.entries.map(\.notification.dbRecordID), [2, 1])
    }

    @MainActor
    func testEvictsOldestOverLimit() {
        let store = NotificationHistoryStore(limit: 2)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        store.append(makeNotification(recID: 1, bundleID: "a", deliveredAt: t0), muted: false)
        store.append(makeNotification(recID: 2, bundleID: "a", deliveredAt: t0.addingTimeInterval(1)), muted: false)
        store.append(makeNotification(recID: 3, bundleID: "a", deliveredAt: t0.addingTimeInterval(2)), muted: false)

        XCTAssertEqual(store.entries.map(\.notification.dbRecordID), [3, 2])
    }

    @MainActor
    func testGroupingByAppOrdersByLatestEntry() {
        let store = NotificationHistoryStore(limit: 100)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        store.append(makeNotification(recID: 1, bundleID: "old", deliveredAt: t0), muted: false)
        store.append(makeNotification(recID: 2, bundleID: "new", deliveredAt: t0.addingTimeInterval(10)), muted: false)
        store.append(makeNotification(recID: 3, bundleID: "old", deliveredAt: t0.addingTimeInterval(5)), muted: false)

        XCTAssertEqual(store.groupedByApp.map(\.bundleID), ["new", "old"])
        XCTAssertEqual(store.groupedByApp.first(where: { $0.bundleID == "old" })?.entries.map(\.notification.dbRecordID), [3, 1])
    }

    @MainActor
    func testRemoveByIDDropsEntry() {
        let store = NotificationHistoryStore(limit: 100)
        let id = UUID()
        store.append(makeNotification(id: id, recID: 1, bundleID: "a", deliveredAt: Date()), muted: false)
        store.remove(id: id)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testClearDropsEverything() {
        let store = NotificationHistoryStore(limit: 100)
        store.append(makeNotification(recID: 1, bundleID: "a", deliveredAt: Date()), muted: false)
        store.append(makeNotification(recID: 2, bundleID: "b", deliveredAt: Date()), muted: true)
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }
}
