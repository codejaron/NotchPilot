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

    func testPreviewReservesStableWidthForNetworkMetricAcrossRateChanges() throws {
        let lowRatePlugin = SystemMonitorPlugin(
            sampler: SystemMonitorStaticSampler(snapshot: SystemMonitorSnapshot(
                cpuUsage: nil,
                memoryUsage: nil,
                downloadBytesPerSecond: 1_000,
                uploadBytesPerSecond: 4_000,
                temperatureCelsius: nil,
                diskFreeBytes: nil,
                batteryPercent: nil,
                blocks: SystemMonitorSnapshot.unavailable.blocks
            )),
            sneakConfiguration: SystemMonitorSneakConfiguration(left: [], right: [.network])
        )
        let highRatePlugin = SystemMonitorPlugin(
            sampler: SystemMonitorStaticSampler(snapshot: SystemMonitorSnapshot(
                cpuUsage: nil,
                memoryUsage: nil,
                downloadBytesPerSecond: 3_200_000,
                uploadBytesPerSecond: 32_000,
                temperatureCelsius: nil,
                diskFreeBytes: nil,
                batteryPercent: nil,
                blocks: SystemMonitorSnapshot.unavailable.blocks
            )),
            sneakConfiguration: SystemMonitorSneakConfiguration(left: [], right: [.network])
        )

        let lowRatePreview = lowRatePlugin.preview(context: Self.context)
        let highRatePreview = highRatePlugin.preview(context: Self.context)

        XCTAssertEqual(
            try XCTUnwrap(lowRatePreview?.width),
            try XCTUnwrap(highRatePreview?.width),
            accuracy: 0.1
        )
    }

    func testRefreshUsesInjectedSamplerSnapshot() async {
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

        await plugin.refresh()

        XCTAssertEqual(plugin.snapshot, expectedSnapshot)
    }

    func testActivateDoesNotBlockMainActorWhenSamplerIsSlow() {
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorSlowSampler(delay: 0.5, snapshot: .unavailable),
            settingsStore: makeSettingsStore()
        )
        let bus = EventBus()

        let start = Date()
        plugin.activate(bus: bus)
        let elapsed = Date().timeIntervalSince(start)
        plugin.deactivate()

        XCTAssertLessThan(elapsed, 0.15)
    }

    func testInitDoesNotBlockMainActorWhenSamplerIsSlow() {
        let start = Date()
        _ = SystemMonitorPlugin(
            sampler: SystemMonitorSlowSampler(delay: 0.5, snapshot: .unavailable),
            settingsStore: makeSettingsStore()
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.15)
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

    func testReenablingGlobalActivitySneaksReissuesPersistentSneakPreview() {
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
        guard case let .sneakPeekRequested(initialRequest)? = receivedEvents.first else {
            XCTFail("Expected initial system monitor sneak request")
            return
        }

        store.activitySneakPreviewsHidden = true

        guard case let .dismissSneakPeek(hiddenRequestID, _)? = receivedEvents.last else {
            XCTFail("Expected system monitor sneak dismissal when hiding activity sneaks")
            return
        }
        XCTAssertEqual(hiddenRequestID, initialRequest.id)

        store.activitySneakPreviewsHidden = false

        guard case let .sneakPeekRequested(restoredRequest)? = receivedEvents.last else {
            XCTFail("Expected system monitor sneak request after showing activity sneaks")
            return
        }
        XCTAssertEqual(restoredRequest.pluginID, plugin.id)
        XCTAssertNotEqual(restoredRequest.id, initialRequest.id)
    }

    func testReenablingSystemMonitorSneakSettingReissuesPersistentSneakPreview() {
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
        guard case let .sneakPeekRequested(initialRequest)? = receivedEvents.first else {
            XCTFail("Expected initial system monitor sneak request")
            return
        }

        store.systemMonitorSneakPreviewEnabled = false

        guard case let .dismissSneakPeek(disabledRequestID, _)? = receivedEvents.last else {
            XCTFail("Expected system monitor sneak dismissal when disabling its sneak setting")
            return
        }
        XCTAssertEqual(disabledRequestID, initialRequest.id)

        store.systemMonitorSneakPreviewEnabled = true

        guard case let .sneakPeekRequested(restoredRequest)? = receivedEvents.last else {
            XCTFail("Expected system monitor sneak request after reenabling its sneak setting")
            return
        }
        XCTAssertEqual(restoredRequest.pluginID, plugin.id)
        XCTAssertNotEqual(restoredRequest.id, initialRequest.id)
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

    func testPreviewReturnsNilWhenSneakPreviewSettingIsDisabled() {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = false
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            settingsStore: store
        )

        let preview = plugin.preview(context: Self.context)

        XCTAssertNil(preview)
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

private struct SystemMonitorSlowSampler: SystemMonitorSampling {
    let delay: TimeInterval
    let storedSnapshot: SystemMonitorSnapshot

    init(delay: TimeInterval, snapshot: SystemMonitorSnapshot) {
        self.delay = delay
        self.storedSnapshot = snapshot
    }

    func snapshot() -> SystemMonitorSnapshot {
        Thread.sleep(forTimeInterval: delay)
        return storedSnapshot
    }
}
