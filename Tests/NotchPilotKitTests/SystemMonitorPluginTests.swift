import CoreGraphics
import XCTest
@testable import NotchPilotKit

@MainActor
final class SystemMonitorPluginTests: XCTestCase {
    func testPluginMetadataMatchesSystemMonitorEntry() {
        let plugin = SystemMonitorPlugin(sampler: SystemMonitorUnavailableSampler())

        XCTAssertEqual(plugin.id, "system-monitor")
        XCTAssertEqual(plugin.title, "System")
        XCTAssertEqual(plugin.iconSystemName, "speedometer")
        XCTAssertEqual(plugin.dockOrder, 90)
        XCTAssertTrue(plugin.isEnabled)
    }

    func testPreviewUsesCompactShellOwnedTextLayoutDimensions() {
        let plugin = SystemMonitorPlugin(sampler: SystemMonitorUnavailableSampler())

        let preview = plugin.preview(context: Self.context)

        XCTAssertNotNil(preview)
        XCTAssertGreaterThan(preview?.width ?? 0, Self.context.notchGeometry.compactSize.width)
        XCTAssertLessThan(preview?.width ?? .greatestFiniteMagnitude, 430)
        XCTAssertEqual(preview?.height, Self.context.notchGeometry.compactSize.height)
    }

    func testPreviewWidthShrinksWithFewerConfiguredSneakSlots() {
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            sneakConfiguration: SystemMonitorSneakConfiguration(left: [.cpu], right: [.network])
        )

        let preview = plugin.preview(context: Self.context)

        XCTAssertNotNil(preview)
        XCTAssertLessThan(preview?.width ?? .greatestFiniteMagnitude, 330)
    }

    func testPreviewStaysCompactWithRealMetricValues() {
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorStaticSampler(snapshot: SystemMonitorSnapshot(
                cpuUsage: 0.22,
                memoryUsage: 0.84,
                downloadBytesPerSecond: 7_000,
                uploadBytesPerSecond: 3_000,
                temperatureCelsius: 71,
                diskFreeBytes: 48_300_000_000,
                batteryPercent: 0.75,
                blocks: SystemMonitorSnapshot.unavailable.blocks
            ))
        )

        let preview = plugin.preview(context: Self.context)

        XCTAssertNotNil(preview)
        XCTAssertLessThan(preview?.width ?? .greatestFiniteMagnitude, 430)
    }

    func testRefreshUsesInjectedSamplerSnapshot() {
        let expectedSnapshot = SystemMonitorSnapshot(
            cpuUsage: 0.22,
            memoryUsage: 0.37,
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 2_000,
            temperatureCelsius: 48,
            diskFreeBytes: 49_000_000_000,
            batteryPercent: 0.84,
            blocks: [
                SystemMonitorBlockSnapshot(kind: .cpu, title: "CPU", summary: "22%", detail: "load", topItems: [])
            ]
        )
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorStaticSampler(snapshot: expectedSnapshot)
        )

        plugin.refresh()

        XCTAssertEqual(plugin.snapshot, expectedSnapshot)
    }

    func testExpandedSnapshotKeepsStableDashboardBlocksByDefault() {
        let plugin = SystemMonitorPlugin(sampler: SystemMonitorUnavailableSampler())

        XCTAssertEqual(plugin.snapshot.blocks.map(\.kind), [.cpu, .memory, .network, .disk])
    }

    func testActivateRequestsPersistentSneakPreviewWhenEnabled() {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = true
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            settingsStore: store
        )
        let bus = EventBus()
        var receivedEvents: [NotchEvent] = []
        bus.subscribe { receivedEvents.append($0) }

        plugin.activate(bus: bus)

        guard case let .sneakPeekRequested(request)? = receivedEvents.first else {
            XCTFail("Expected system monitor sneak request")
            return
        }
        XCTAssertEqual(request.pluginID, plugin.id)
        XCTAssertEqual(request.priority, 2_000)
        XCTAssertEqual(request.target, .allScreens)
        XCTAssertFalse(request.isInteractive)
        XCTAssertNil(request.autoDismissAfter)
    }

    func testDeactivateDismissesPersistentSneakPreviewRequest() {
        let store = makeSettingsStore()
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            settingsStore: store
        )
        let bus = EventBus()
        var receivedEvents: [NotchEvent] = []
        bus.subscribe { receivedEvents.append($0) }

        plugin.activate(bus: bus)
        guard case let .sneakPeekRequested(request)? = receivedEvents.first else {
            XCTFail("Expected system monitor sneak request")
            return
        }

        plugin.deactivate()

        guard case let .dismissSneakPeek(requestID, target)? = receivedEvents.last else {
            XCTFail("Expected system monitor sneak dismissal")
            return
        }
        XCTAssertEqual(requestID, request.id)
        XCTAssertEqual(target, .allScreens)
    }

    func testActivateDoesNotRequestSneakPreviewWhenSettingIsDisabled() {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = false
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            settingsStore: store
        )
        let bus = EventBus()
        var receivedEvents: [NotchEvent] = []
        bus.subscribe { receivedEvents.append($0) }

        plugin.activate(bus: bus)

        XCTAssertTrue(receivedEvents.isEmpty)
    }

    func testPluginUsesSettingsStoreSneakConfiguration() {
        let store = makeSettingsStore()
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            left: [.disk],
            right: [.battery, .network]
        )

        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            settingsStore: store
        )

        XCTAssertEqual(plugin.sneakConfiguration.leftMetrics, [.disk])
        XCTAssertEqual(plugin.sneakConfiguration.rightMetrics, [.battery, .network])
    }

    private static let context = NotchContext(
        screenID: "test-screen",
        notchState: .previewClosed,
        notchGeometry: NotchGeometry(
            compactSize: CGSize(width: 185, height: 32),
            expandedSize: CGSize(width: 520, height: 320)
        ),
        isPrimaryScreen: true
    )

    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "SystemMonitorPluginTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: FileManager.default.temporaryDirectory
        )
    }
}
