import AppKit
import XCTest
@testable import NotchPilotKit

final class MouseActivityMonitorTests: XCTestCase {
    @MainActor
    func testMonitorInstallsSingleEventPairForMultipleSubscribers() {
        let eventMonitor = TestMouseEventMonitor()
        let monitor = MouseActivityMonitor(eventMonitor: eventMonitor)

        let first = monitor.addSubscriber { _ in .passThrough }
        let second = monitor.addSubscriber { _ in .passThrough }

        XCTAssertEqual(eventMonitor.localInstallCount, 1)
        XCTAssertEqual(eventMonitor.globalInstallCount, 1)

        monitor.removeSubscriber(first)
        XCTAssertEqual(eventMonitor.removeCallCount, 0)

        monitor.removeSubscriber(second)
        XCTAssertEqual(eventMonitor.removeCallCount, 2)
    }

    @MainActor
    func testLocalEventIsConsumedWhenAnySubscriberConsumesIt() throws {
        let eventMonitor = TestMouseEventMonitor()
        let monitor = MouseActivityMonitor(eventMonitor: eventMonitor)
        var observedScopes: [MouseActivityScope] = []

        monitor.addSubscriber { activity in
            observedScopes.append(activity.scope)
            return .passThrough
        }
        monitor.addSubscriber { activity in
            observedScopes.append(activity.scope)
            return .consumeEvent
        }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
        let result = eventMonitor.localHandler?(event)

        XCTAssertNil(result)
        XCTAssertEqual(observedScopes, [.local, .local])
    }
}

private final class TestMouseEventMonitor: MouseEventMonitoring {
    private let localToken = NSObject()
    private let globalToken = NSObject()
    private(set) var localInstallCount = 0
    private(set) var globalInstallCount = 0
    private(set) var removeCallCount = 0
    private(set) var localHandler: ((NSEvent) -> NSEvent?)?

    func addLocalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        localInstallCount += 1
        localHandler = handler
        return localToken
    }

    func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any? {
        globalInstallCount += 1
        return globalToken
    }

    func removeMonitor(_ monitor: Any) {
        removeCallCount += 1
    }
}
