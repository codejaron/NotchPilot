import CoreGraphics
import XCTest
@testable import NotchPilotKit

@MainActor
final class SystemMonitorPluginTests: XCTestCase {
    func testPluginMetadataMatchesSystemMonitorEntry() {
        let plugin = SystemMonitorPlugin(sampler: SystemMonitorUnavailableSampler())

        XCTAssertEqual(plugin.id, "system-monitor")
        XCTAssertEqual(plugin.title, "System")
        XCTAssertEqual(plugin.iconSystemName, "cpu")
        XCTAssertEqual(plugin.dockOrder, 90)
        XCTAssertTrue(plugin.isEnabled)
    }

    func testPluginReflectsSystemMonitorAvailabilitySetting() {
        let store = makeSettingsStore()
        store.systemMonitorEnabled = false

        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            settingsStore: store
        )

        XCTAssertFalse(plugin.isEnabled)
        XCTAssertNil(plugin.preview(context: Self.context))

        store.systemMonitorEnabled = true

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
        XCTAssertEqual(request.priority, SneakPeekRequestPriority.systemMonitor)
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

    // MARK: - Sneak mode integration

    func testAmbientModeDoesNotEmitSneakRequestUntilAlertFires() async {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = true
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            mode: .ambient,
            left: [],
            right: [],
            reactive: [.memory, .cpu]
        )
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorStaticSampler(snapshot: Self.calmSnapshot),
            settingsStore: store,
            alertEngine: SystemMonitorAlertEngine(
                rules: [Self.memoryWarnRule],
                clock: SystemMonitorSystemClock()
            )
        )
        let bus = EventBus()
        var receivedEvents: [NotchEvent] = []
        bus.subscribe { receivedEvents.append($0) }

        plugin.activate(bus: bus)
        XCTAssertTrue(
            receivedEvents.allSatisfy {
                if case .sneakPeekRequested = $0 { return false }
                return true
            },
            "Ambient mode must not emit a sneak request before any alert fires"
        )
        XCTAssertNil(plugin.preview(context: Self.context))
    }

    func testAmbientModeEmitsSneakRequestWhenAlertFiresAndDismissesWhenCleared() async {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = true
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            mode: .ambient,
            left: [],
            right: [],
            reactive: [.memory, .cpu]
        )
        let firingSampler = MutableSnapshotSampler(snapshot: Self.memoryHighSnapshot)
        let plugin = SystemMonitorPlugin(
            sampler: firingSampler,
            settingsStore: store,
            alertEngine: SystemMonitorAlertEngine(
                rules: [Self.memoryWarnRule],
                clock: SystemMonitorSystemClock()
            )
        )
        let bus = EventBus()
        var receivedEvents: [NotchEvent] = []
        bus.subscribe { receivedEvents.append($0) }

        plugin.activate(bus: bus)
        await plugin.refresh()

        let sneakRequests: [SneakPeekRequest] = receivedEvents.compactMap {
            if case let .sneakPeekRequested(request) = $0 { return request }
            return nil
        }
        XCTAssertEqual(sneakRequests.count, 1, "Ambient sneak should be emitted once a reactive alert is firing")
        XCTAssertEqual(sneakRequests.first?.pluginID, plugin.id)

        let preview = plugin.preview(context: Self.context)
        XCTAssertNotNil(preview)

        firingSampler.storedSnapshot = Self.calmSnapshot
        await plugin.refresh()

        let dismissals: [UUID] = receivedEvents.compactMap {
            if case let .dismissSneakPeek(requestID, _) = $0 { return requestID }
            return nil
        }
        XCTAssertEqual(dismissals.last, sneakRequests.first?.id)
        XCTAssertNil(plugin.preview(context: Self.context))
    }

    func testPinnedReactiveModeInjectsFiringReactiveMetricIntoRightSlot() async {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = true
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            mode: .pinnedReactive,
            left: [.cpu],
            right: [.network],
            reactive: [.memory, .temperature]
        )
        let firingSampler = MutableSnapshotSampler(snapshot: Self.memoryHighSnapshot)
        let plugin = SystemMonitorPlugin(
            sampler: firingSampler,
            settingsStore: store,
            alertEngine: SystemMonitorAlertEngine(
                rules: [Self.memoryWarnRule],
                clock: SystemMonitorSystemClock()
            )
        )

        await plugin.refresh()

        let composed = SystemMonitorSneakComposer.compose(
            base: store.systemMonitorSneakConfiguration,
            activeAlerts: plugin.activeAlerts
        )
        XCTAssertEqual(composed.leftMetrics, [.cpu], "Pinned left slot must remain stable")
        XCTAssertEqual(composed.rightMetrics.first, .memory, "Firing reactive metric should take priority on the right slot")
    }

    func testPinnedReactiveModeRevertsRightSlotAfterAlertClears() async {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = true
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            mode: .pinnedReactive,
            left: [.cpu],
            right: [.network],
            reactive: [.memory]
        )
        let firingSampler = MutableSnapshotSampler(snapshot: Self.memoryHighSnapshot)
        let plugin = SystemMonitorPlugin(
            sampler: firingSampler,
            settingsStore: store,
            alertEngine: SystemMonitorAlertEngine(
                rules: [Self.memoryWarnRule],
                clock: SystemMonitorSystemClock()
            )
        )

        await plugin.refresh()
        XCTAssertEqual(
            SystemMonitorSneakComposer.compose(
                base: store.systemMonitorSneakConfiguration,
                activeAlerts: plugin.activeAlerts
            ).rightMetrics.first,
            .memory
        )

        firingSampler.storedSnapshot = Self.calmSnapshot
        await plugin.refresh()
        XCTAssertEqual(plugin.activeAlerts, [:])
        XCTAssertEqual(
            SystemMonitorSneakComposer.compose(
                base: store.systemMonitorSneakConfiguration,
                activeAlerts: plugin.activeAlerts
            ).rightMetrics,
            [.network],
            "Right slot must revert to the pinned metric once the alert clears"
        )
    }

    func testLoweringCpuThresholdViaSettingsStoreFiresAlertOnNextSnapshotApplication() async {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = true
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            mode: .ambient,
            left: [],
            right: [],
            reactive: [.cpu]
        )

        let cpuHotSnapshot = SystemMonitorSnapshot(
            cpuUsage: 0.6,
            memoryPressure: 0.2,
            memoryUsage: 0.2,
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 0,
            temperatureCelsius: 45,
            diskFreeBytes: 100_000_000_000,
            batteryPercent: 0.9,
            blocks: SystemMonitorSnapshot.unavailable.blocks
        )
        let firingSampler = MutableSnapshotSampler(snapshot: cpuHotSnapshot)
        let clock = TestPluginMutableClock(start: Date(timeIntervalSince1970: 0))
        let engine = SystemMonitorAlertEngine(
            rules: SystemMonitorAlertRuleCatalog.rules(for: store.systemMonitorAlertThresholds),
            clock: clock
        )
        let plugin = SystemMonitorPlugin(
            sampler: firingSampler,
            settingsStore: store,
            alertEngine: engine
        )

        // 60% CPU stays under the default 85% threshold even after the
        // sustain window elapses.
        clock.advance(by: 10)
        await plugin.refresh()
        XCTAssertTrue(plugin.activeAlerts.isEmpty)

        // User drops the CPU threshold to 50%; the plugin rebuilds rules and
        // re-evaluates against the latest snapshot, so the sustain timer
        // starts ticking from "now". After the 5s window elapses and another
        // sample arrives, the rule must fire.
        store.systemMonitorAlertThresholds = store.systemMonitorAlertThresholds
            .setting(50, for: .cpu)

        clock.advance(by: 5)
        await plugin.refresh()

        XCTAssertEqual(plugin.activeAlerts[.cpu]?.metric, .cpu)
    }

    func testAlwaysOnModePreservesLegacyBehavior() {
        let store = makeSettingsStore()
        store.systemMonitorSneakPreviewEnabled = true
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            mode: .alwaysOn,
            left: [.cpu, .memory],
            right: [.network, .temperature]
        )
        let plugin = SystemMonitorPlugin(
            sampler: SystemMonitorUnavailableSampler(),
            settingsStore: store,
            alertEngine: SystemMonitorAlertEngine(rules: [], clock: SystemMonitorSystemClock())
        )
        let bus = EventBus()
        var receivedEvents: [NotchEvent] = []
        bus.subscribe { receivedEvents.append($0) }

        plugin.activate(bus: bus)

        guard case .sneakPeekRequested = receivedEvents.first else {
            XCTFail("Always-on mode should emit a sneak request as soon as the plugin activates")
            return
        }
        let composed = SystemMonitorSneakComposer.compose(
            base: store.systemMonitorSneakConfiguration,
            activeAlerts: plugin.activeAlerts
        )
        XCTAssertEqual(composed.leftMetrics, [.cpu, .memory])
        XCTAssertEqual(composed.rightMetrics, [.network, .temperature])
    }

    // MARK: - Fixtures

    private static let memoryWarnRule = SystemMonitorAlertRule(
        id: "memory.warn",
        metric: .memory,
        comparison: .greaterThan,
        threshold: 70,
        sustainSeconds: 0,
        severity: .warn
    )

    private static let calmSnapshot = SystemMonitorSnapshot(
        cpuUsage: 0.1,
        memoryPressure: 0.2,
        memoryUsage: 0.2,
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        temperatureCelsius: 45,
        diskFreeBytes: 100_000_000_000,
        batteryPercent: 0.9,
        blocks: SystemMonitorSnapshot.unavailable.blocks
    )

    private static let memoryHighSnapshot = SystemMonitorSnapshot(
        cpuUsage: 0.1,
        memoryPressure: 0.92,
        memoryUsage: 0.95,
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        temperatureCelsius: 50,
        diskFreeBytes: 100_000_000_000,
        batteryPercent: 0.9,
        blocks: SystemMonitorSnapshot.unavailable.blocks
    )

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

private final class TestPluginMutableClock: SystemMonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        self.current = start
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class MutableSnapshotSampler: SystemMonitorSampling, @unchecked Sendable {
    private let storage = NSLock()
    private var current: SystemMonitorSnapshot

    init(snapshot: SystemMonitorSnapshot) {
        self.current = snapshot
    }

    var storedSnapshot: SystemMonitorSnapshot {
        get {
            storage.lock()
            defer { storage.unlock() }
            return current
        }
        set {
            storage.lock()
            current = newValue
            storage.unlock()
        }
    }

    func snapshot() -> SystemMonitorSnapshot {
        storedSnapshot
    }
}
