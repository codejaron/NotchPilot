import Combine
import XCTest
@testable import NotchPilotKit

final class NotificationsPluginTests: XCTestCase {
    private final class FakeObserver: NotificationDatabaseObserving, @unchecked Sendable {
        var onNotifications: ((@Sendable ([SystemNotification]) -> Void))?
        var onStateChange: ((@Sendable (NotificationsPluginRuntimeState) -> Void))?
        var onKnownAppsLoaded: ((@Sendable ([String]) -> Void))?
        var onDatabasePathResolved: ((@Sendable (String?) -> Void))?

        var didStart = false
        var didStop = false

        func start() { didStart = true }
        func stop() { didStop = true }

        // Test helpers
        func emit(_ ns: [SystemNotification]) { onNotifications?(ns) }
        func reportState(_ s: NotificationsPluginRuntimeState) { onStateChange?(s) }
        func reportKnownApps(_ ids: [String]) { onKnownAppsLoaded?(ids) }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        suiteName = "NotificationsPluginTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempHomeURL)
    }

    @MainActor
    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: defaults, fileManager: .default, homeDirectoryURL: tempHomeURL)
    }

    @MainActor
    func testMetadataMatchesSpec() {
        let store = makeStore()
        let plugin = NotificationsPlugin(observer: FakeObserver(), settingsStore: store)
        XCTAssertEqual(plugin.id, "notifications")
        XCTAssertEqual(plugin.dockOrder, 95)
        XCTAssertEqual(plugin.iconSystemName, "bell.badge")
    }

    @MainActor
    func testActivateStartsObserverWhenEnabled() {
        let store = makeStore()
        store.notificationsEnabled = true
        let fake = FakeObserver()
        let plugin = NotificationsPlugin(observer: fake, settingsStore: store)

        let bus = EventBus()
        plugin.activate(bus: bus)
        XCTAssertTrue(fake.didStart)
    }

    @MainActor
    func testActivateSkipsObserverWhenDisabled() {
        let store = makeStore()
        store.notificationsEnabled = false
        let fake = FakeObserver()
        let plugin = NotificationsPlugin(observer: fake, settingsStore: store)

        plugin.activate(bus: EventBus())
        XCTAssertFalse(fake.didStart)
    }

    @MainActor
    func testEmitsSneakPeekForWhitelistedApp() {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.tencent.xinWeChat"]

        let fake = FakeObserver()
        let plugin = NotificationsPlugin(observer: fake, settingsStore: store)
        let bus = EventBus()
        var sneakEvents: [SneakPeekRequest] = []
        _ = bus.subscribe { event in
            if case .sneakPeekRequested(let req) = event {
                sneakEvents.append(req)
            }
        }
        plugin.activate(bus: bus)

        fake.emit([
            SystemNotification(
                dbRecordID: 1,
                bundleIdentifier: "com.tencent.xinWeChat",
                title: "张三", subtitle: nil, body: "你好",
                deliveredAt: Date()
            )
        ])

        XCTAssertEqual(sneakEvents.count, 1)
        XCTAssertEqual(sneakEvents.first?.pluginID, "notifications")
        XCTAssertEqual(sneakEvents.first?.priority, SneakPeekRequestPriority.notifications)
    }

    @MainActor
    func testRecordsButDoesNotEmitForMutedApp() {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = [] // empty

        let fake = FakeObserver()
        let plugin = NotificationsPlugin(observer: fake, settingsStore: store)
        let bus = EventBus()
        var sneakEvents: [SneakPeekRequest] = []
        _ = bus.subscribe { event in
            if case .sneakPeekRequested(let req) = event {
                sneakEvents.append(req)
            }
        }
        plugin.activate(bus: bus)

        fake.emit([
            SystemNotification(
                dbRecordID: 1,
                bundleIdentifier: "com.tencent.xinWeChat",
                title: "张三", body: "你好",
                deliveredAt: Date()
            )
        ])

        XCTAssertTrue(sneakEvents.isEmpty)
        XCTAssertEqual(plugin.historyStore.entries.count, 1)
        XCTAssertTrue(plugin.historyStore.entries.first?.muted ?? false)
    }

    @MainActor
    func testKnownAppsCachePopulatesOnArrival() {
        let store = makeStore()
        store.notificationsEnabled = true
        let fake = FakeObserver()
        let plugin = NotificationsPlugin(observer: fake, settingsStore: store)
        plugin.activate(bus: EventBus())

        fake.emit([
            SystemNotification(
                dbRecordID: 1,
                bundleIdentifier: "com.tencent.xinWeChat",
                title: "T", body: "B",
                deliveredAt: Date()
            )
        ])

        XCTAssertNotNil(store.notificationsKnownAppsCache["com.tencent.xinWeChat"])
    }

    @MainActor
    func testPreloadsKnownAppsCacheFromObserverCallback() {
        let store = makeStore()
        store.notificationsEnabled = true
        XCTAssertTrue(store.notificationsKnownAppsCache.isEmpty)

        let fake = FakeObserver()
        let plugin = NotificationsPlugin(observer: fake, settingsStore: store)
        plugin.activate(bus: EventBus())

        fake.reportKnownApps([
            "com.tencent.xinWeChat",
            "com.apple.Mail",
            "com.apple.iCal"
        ])

        XCTAssertEqual(store.notificationsKnownAppsCache.count, 3)
        XCTAssertNotNil(store.notificationsKnownAppsCache["com.tencent.xinWeChat"])
        XCTAssertNotNil(store.notificationsKnownAppsCache["com.apple.Mail"])
        XCTAssertNotNil(store.notificationsKnownAppsCache["com.apple.iCal"])
        XCTAssertEqual(plugin.diagnostics.knownAppCount, 3)
    }
}
