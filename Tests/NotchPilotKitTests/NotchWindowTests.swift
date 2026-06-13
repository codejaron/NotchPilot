import CoreGraphics
import AppKit
import XCTest
@testable import NotchPilotKit

final class NotchWindowTests: XCTestCase {
    func testDefaultStyleMaskDoesNotRequestSystemHUDChrome() {
        let styleMask = NotchWindowStyle.defaultStyleMask

        XCTAssertTrue(styleMask.contains(.borderless))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(styleMask.contains(.utilityWindow))
        XCTAssertFalse(styleMask.contains(.hudWindow))
    }

    func testFrameRefreshPlanSkipsWindowUpdateWhenTargetFrameIsUnchanged() {
        let frame = CGRect(x: 100, y: 200, width: 520, height: 340)

        let plan = NotchWindowFrameRefreshPlan.resolve(currentFrame: frame, targetFrame: frame)

        XCTAssertFalse(plan.needsWindowFrameUpdate)
        XCTAssertEqual(plan.targetFrame, frame)
    }

    func testFrameRefreshPlanUpdatesWindowWhenTargetFrameChanges() {
        let currentFrame = CGRect(x: 100, y: 200, width: 520, height: 340)
        let targetFrame = CGRect(x: 120, y: 210, width: 600, height: 340)

        let plan = NotchWindowFrameRefreshPlan.resolve(currentFrame: currentFrame, targetFrame: targetFrame)

        XCTAssertTrue(plan.needsWindowFrameUpdate)
        XCTAssertEqual(plan.targetFrame, targetFrame)
    }

    func testInteractionFrameCacheReusesFrameUntilInvalidated() {
        var cache = NotchWindowInteractionFrameCache()
        var resolveCount = 0
        let first = cache.frame {
            resolveCount += 1
            return CGRect(x: 10, y: 20, width: 30, height: 40)
        }
        let second = cache.frame {
            resolveCount += 1
            return CGRect(x: 50, y: 60, width: 70, height: 80)
        }

        XCTAssertEqual(first, CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(second, first)
        XCTAssertEqual(resolveCount, 1)

        cache.invalidate()
        let third = cache.frame {
            resolveCount += 1
            return CGRect(x: 50, y: 60, width: 70, height: 80)
        }

        XCTAssertEqual(third, CGRect(x: 50, y: 60, width: 70, height: 80))
        XCTAssertEqual(resolveCount, 2)
    }

    @MainActor
    func testWindowCloseDoesNotReleaseARCManagedInstance() {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )
        let pluginManager = PluginManager()
        let window = NotchWindow(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: NotchWindowTestMouseActivityMonitor()
        )

        XCTAssertFalse(window.isReleasedWhenClosed)

        window.close()
    }
}

@MainActor
private final class NotchWindowTestMouseActivityMonitor: MouseActivityMonitoring {
    func addSubscriber(
        _ handler: @escaping @MainActor (MouseActivityEvent) -> MouseActivityHandlingResult
    ) -> UUID {
        UUID()
    }

    func removeSubscriber(_ token: UUID) {}
}
