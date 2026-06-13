import CoreGraphics
import XCTest
@testable import NotchPilotKit

@MainActor
final class MultiScreenManagerTests: XCTestCase {
    func testPersistentSneakPeekRequestReplaysToNewMatchingScreenSession() {
        let source = ScreenDescriptorSource([
            screen(id: "primary", isPrimary: true),
        ])
        let manager = makeManager(
            descriptors: { source.descriptors },
            activeScreenID: { "primary" },
            primaryScreenID: { "primary" }
        )
        manager.synchronizeScreens()

        let request = SneakPeekRequest(
            pluginID: "system-monitor",
            priority: SneakPeekRequestPriority.systemMonitor,
            target: .allScreens,
            isInteractive: false,
            autoDismissAfter: nil
        )

        manager.handle(event: .sneakPeekRequested(request))
        XCTAssertEqual(manager.sessions["primary"]?.currentSneakPeek, request)

        source.descriptors.append(screen(id: "secondary", x: 1512))
        manager.synchronizeScreens()

        XCTAssertEqual(manager.sessions["secondary"]?.currentSneakPeek, request)
    }

    func testAutoDismissingSneakPeekRequestDoesNotReplayToNewScreenSession() {
        let source = ScreenDescriptorSource([
            screen(id: "primary", isPrimary: true),
        ])
        let manager = makeManager(
            descriptors: { source.descriptors },
            activeScreenID: { "primary" },
            primaryScreenID: { "primary" }
        )
        manager.synchronizeScreens()

        let request = SneakPeekRequest(
            pluginID: "media",
            priority: SneakPeekRequestPriority.mediaPlayback,
            target: .allScreens,
            isInteractive: false,
            autoDismissAfter: 2
        )

        manager.handle(event: .sneakPeekRequested(request))
        XCTAssertEqual(manager.sessions["primary"]?.currentSneakPeek, request)

        source.descriptors.append(screen(id: "secondary", x: 1512))
        manager.synchronizeScreens()

        XCTAssertNil(manager.sessions["secondary"]?.currentSneakPeek)
    }

    func testDismissedPersistentSneakPeekDoesNotReplayToNewScreenSession() {
        let source = ScreenDescriptorSource([
            screen(id: "primary", isPrimary: true),
        ])
        let manager = makeManager(
            descriptors: { source.descriptors },
            activeScreenID: { "primary" },
            primaryScreenID: { "primary" }
        )
        manager.synchronizeScreens()

        let request = SneakPeekRequest(
            pluginID: "system-monitor",
            priority: SneakPeekRequestPriority.systemMonitor,
            target: .allScreens,
            isInteractive: false,
            autoDismissAfter: nil
        )

        manager.handle(event: .sneakPeekRequested(request))
        manager.handle(event: .dismissSneakPeek(requestID: request.id, target: .allScreens))

        source.descriptors.append(screen(id: "secondary", x: 1512))
        manager.synchronizeScreens()

        XCTAssertNil(manager.sessions["secondary"]?.currentSneakPeek)
    }

    private func makeManager(
        descriptors: @escaping @MainActor () -> [ScreenDescriptor],
        activeScreenID: @escaping @MainActor () -> String?,
        primaryScreenID: @escaping @MainActor () -> String?
    ) -> MultiScreenManager {
        MultiScreenManager(
            bus: EventBus(),
            pluginManager: PluginManager(),
            screenDescriptorProvider: descriptors,
            activeScreenIDProvider: activeScreenID,
            primaryScreenIDProvider: primaryScreenID,
            windowFactory: { _, _ in nil }
        )
    }

    private func screen(
        id: String,
        x: CGFloat = 0,
        isPrimary: Bool = false
    ) -> ScreenDescriptor {
        ScreenDescriptor(
            id: id,
            frame: CGRect(x: x, y: 0, width: 1512, height: 982),
            isPrimary: isPrimary,
            closedNotchSize: CGSize(width: 240, height: 36)
        )
    }
}

@MainActor
private final class ScreenDescriptorSource {
    var descriptors: [ScreenDescriptor]

    init(_ descriptors: [ScreenDescriptor]) {
        self.descriptors = descriptors
    }
}
