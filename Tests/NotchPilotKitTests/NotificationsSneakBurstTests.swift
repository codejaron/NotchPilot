import XCTest
@testable import NotchPilotKit

final class NotificationsSneakBurstTests: XCTestCase {
    private func note(bundleID: String, at offset: TimeInterval) -> SystemNotification {
        SystemNotification(
            dbRecordID: 1,
            bundleIdentifier: bundleID,
            deliveredAt: Date(timeIntervalSinceReferenceDate: offset)
        )
    }

    func testFirstArrivalEmits() {
        var burst = NotificationsSneakBurst(windowDuration: 1.0)
        let result = burst.observe(note(bundleID: "a", at: 0), now: Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(result, .emit(count: 1))
    }

    func testSameAppWithinWindowFolds() {
        var burst = NotificationsSneakBurst(windowDuration: 1.0)
        _ = burst.observe(note(bundleID: "a", at: 0), now: Date(timeIntervalSinceReferenceDate: 0))
        let result = burst.observe(note(bundleID: "a", at: 0.3), now: Date(timeIntervalSinceReferenceDate: 0.3))
        XCTAssertEqual(result, .fold(count: 2))
    }

    func testSameAppAfterWindowReEmitsAndCountResets() {
        var burst = NotificationsSneakBurst(windowDuration: 1.0)
        _ = burst.observe(note(bundleID: "a", at: 0), now: Date(timeIntervalSinceReferenceDate: 0))
        let result = burst.observe(note(bundleID: "a", at: 2.0), now: Date(timeIntervalSinceReferenceDate: 2.0))
        XCTAssertEqual(result, .emit(count: 1))
    }

    func testDifferentAppWithinAnotherAppsWindowEmits() {
        var burst = NotificationsSneakBurst(windowDuration: 1.0)
        _ = burst.observe(note(bundleID: "a", at: 0), now: Date(timeIntervalSinceReferenceDate: 0))
        let result = burst.observe(note(bundleID: "b", at: 0.3), now: Date(timeIntervalSinceReferenceDate: 0.3))
        XCTAssertEqual(result, .emit(count: 1))
    }
}
