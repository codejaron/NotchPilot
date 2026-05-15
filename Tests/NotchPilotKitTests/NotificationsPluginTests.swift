import Combine
import XCTest
@testable import NotchPilotKit

final class NotificationsPluginTests: XCTestCase {
    private static func previewContext(currentSneakPeek: SneakPeekRequest? = nil) -> NotchContext {
        NotchContext(
            screenID: "test-screen",
            notchState: .previewClosed,
            notchGeometry: NotchGeometry(
                compactSize: CGSize(width: 185, height: 32),
                expandedSize: CGSize(width: 520, height: 320)
            ),
            isPrimaryScreen: true,
            currentSneakPeek: currentSneakPeek
        )
    }

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

    private final class StubWorkspace: NotificationAppDirectoryWorkspace {
        var lookups: [String: (url: URL, name: String)] = [:]

        func appURL(forBundleIdentifier id: String) -> URL? {
            lookups[id]?.url
        }

        func appName(forBundleIdentifier id: String) -> String? {
            lookups[id]?.name
        }
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
        XCTAssertEqual(sneakEvents.first?.autoDismissAfter, 2.0)
    }

    @MainActor
    func testFreshNotificationPreviewRendersBeforeObserverReportsRunning() throws {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.chat"]

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
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ada", body: "Just arrived",
                deliveredAt: Date()
            )
        ])

        let request = try XCTUnwrap(sneakEvents.first)
        XCTAssertNotNil(
            plugin.preview(context: Self.previewContext(currentSneakPeek: request)),
            "The just-emitted notification request should be renderable even if the observer state update arrives just after the notification callback."
        )
    }

    @MainActor
    func testSameAppBurstPreviewExpandsToIncludePreviousMessages() throws {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.chat"]

        let singleFake = FakeObserver()
        let singlePlugin = NotificationsPlugin(observer: singleFake, settingsStore: store)
        let singleBus = EventBus()
        var singleSneaks: [SneakPeekRequest] = []
        _ = singleBus.subscribe { event in
            if case .sneakPeekRequested(let req) = event {
                singleSneaks.append(req)
            }
        }
        singlePlugin.activate(bus: singleBus)
        singleFake.reportState(.running(lastEventAt: nil))

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        singleFake.emit([
            SystemNotification(
                dbRecordID: 1,
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ada", body: "First",
                deliveredAt: base
            )
        ])
        let singleRequest = try XCTUnwrap(singleSneaks.first)
        let singleHeight = try XCTUnwrap(
            singlePlugin.preview(context: Self.previewContext(currentSneakPeek: singleRequest))?.height
        )

        let burstFake = FakeObserver()
        let burstPlugin = NotificationsPlugin(observer: burstFake, settingsStore: store)
        let burstBus = EventBus()
        var burstSneaks: [SneakPeekRequest] = []
        _ = burstBus.subscribe { event in
            if case .sneakPeekRequested(let req) = event {
                burstSneaks.append(req)
            }
        }
        burstPlugin.activate(bus: burstBus)
        burstFake.reportState(.running(lastEventAt: nil))
        burstFake.emit([
            SystemNotification(
                dbRecordID: 1,
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ada", body: "First",
                deliveredAt: base
            ),
            SystemNotification(
                dbRecordID: 2,
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ben", body: "Second",
                deliveredAt: base.addingTimeInterval(0.4)
            )
        ])
        XCTAssertEqual(burstSneaks.count, 1)
        let burstHeight = try XCTUnwrap(
            burstPlugin.preview(context: Self.previewContext(currentSneakPeek: burstSneaks[0]))?.height
        )

        XCTAssertGreaterThan(
            burstHeight,
            singleHeight,
            "Burst previews should make room for earlier message content instead of replacing it with only the latest notification."
        )
    }

    @MainActor
    func testSeparateObserverBatchesQueueSeparateSneaks() {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.chat"]

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
        fake.reportState(.running(lastEventAt: nil))

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        fake.emit([
            SystemNotification(
                dbRecordID: 1,
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ada", body: "Still visible",
                deliveredAt: base
            )
        ])
        fake.emit([
            SystemNotification(
                dbRecordID: 2,
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ben", body: "Before auto dismiss",
                deliveredAt: base.addingTimeInterval(2.0)
            )
        ])

        XCTAssertEqual(sneakEvents.count, 2)
        XCTAssertEqual(sneakEvents.map(\.autoDismissAfter), [2.0, 2.0])
    }

    @MainActor
    func testSameAppBurstPreviewCapsVisibleBatchAtThreeMessages() throws {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.chat"]

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
        fake.reportState(.running(lastEventAt: nil))

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        fake.emit((1...4).map { index in
            SystemNotification(
                dbRecordID: Int64(index),
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Sender \(index)", body: "Message \(index)",
                deliveredAt: base.addingTimeInterval(TimeInterval(index) * 0.1)
            )
        })
        XCTAssertEqual(sneakEvents.count, 2)
        let firstBatchHeight = try XCTUnwrap(
            plugin.preview(context: Self.previewContext(currentSneakPeek: sneakEvents[0]))?.height
        )
        let secondBatchHeight = try XCTUnwrap(
            plugin.preview(context: Self.previewContext(currentSneakPeek: sneakEvents[1]))?.height
        )

        XCTAssertGreaterThan(firstBatchHeight, secondBatchHeight)
    }

    @MainActor
    func testSameAppBurstDoesNotReserveBadgeWidth() throws {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.chat"]

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
        fake.reportState(.running(lastEventAt: nil))

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        fake.emit([
            SystemNotification(
                dbRecordID: 1,
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ada", body: "One",
                deliveredAt: base
            )
        ])
        let singleWidth = try XCTUnwrap(
            plugin.preview(context: Self.previewContext(currentSneakPeek: sneakEvents[0]))?.width
        )

        fake.emit([
            SystemNotification(
                dbRecordID: 2,
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Ben", body: "Two",
                deliveredAt: base.addingTimeInterval(0.1)
            )
        ])
        let burstWidth = try XCTUnwrap(
            plugin.preview(context: Self.previewContext(currentSneakPeek: sneakEvents[1]))?.width
        )

        XCTAssertEqual(burstWidth, singleWidth)
    }

    @MainActor
    func testFourNotificationsEmitTwoQueuedSneaksWithTwoSecondDismissal() {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsSneakPreviewEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.chat"]

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
        fake.reportState(.running(lastEventAt: nil))

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        fake.emit((1...4).map { index in
            SystemNotification(
                dbRecordID: Int64(index),
                bundleIdentifier: "com.chat",
                appDisplayName: "Chat",
                title: "Sender \(index)", body: "Message \(index)",
                deliveredAt: base.addingTimeInterval(TimeInterval(index) * 0.1)
            )
        })

        XCTAssertEqual(sneakEvents.count, 2)
        XCTAssertEqual(sneakEvents.map(\.autoDismissAfter), [2.0, 2.0])
    }

    @MainActor
    func testIgnoresNonWhitelistedApp() {
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
        XCTAssertTrue(plugin.historyStore.entries.isEmpty)
        XCTAssertEqual(
            store.notificationsKnownAppsCache["com.tencent.xinWeChat"]?.discoverySource,
            .notificationArrival
        )
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

        let workspace = StubWorkspace()
        workspace.lookups = [
            "com.tencent.xinWeChat": (URL(fileURLWithPath: "/Applications/WeChat.app"), "WeChat"),
            "com.apple.Mail": (URL(fileURLWithPath: "/System/Applications/Mail.app"), "Mail"),
            "com.apple.iCal": (URL(fileURLWithPath: "/System/Applications/Calendar.app"), "Calendar"),
        ]

        let fake = FakeObserver()
        let plugin = NotificationsPlugin(
            observer: fake,
            settingsStore: store,
            appDirectory: NotificationAppDirectory(workspace: workspace)
        )
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

    @MainActor
    func testPreloadedKnownAppsSkipUnresolvedHistoricalBundleIDsButKeepObservedSources() {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsKnownAppsCache = [
            "com.iphone.Bank": KnownApp(
                bundleIdentifier: "com.iphone.Bank",
                displayName: "Bank",
                iconCachePath: nil,
                discoverySource: .notificationArrival
            )
        ]

        let workspace = StubWorkspace()
        workspace.lookups["com.chat"] = (
            URL(fileURLWithPath: "/Applications/Chat.app"),
            "Chat"
        )

        let fake = FakeObserver()
        let plugin = NotificationsPlugin(
            observer: fake,
            settingsStore: store,
            appDirectory: NotificationAppDirectory(workspace: workspace)
        )
        plugin.activate(bus: EventBus())

        fake.reportKnownApps([
            "com.chat",
            "com.iphone.Bank",
            "com.deleted.OldApp",
            "com.apple.background-service"
        ])

        XCTAssertEqual(
            Set(store.notificationsKnownAppsCache.keys),
            ["com.chat", "com.iphone.Bank"]
        )
        XCTAssertEqual(plugin.diagnostics.knownAppCount, 2)
    }

    @MainActor
    func testKnownAppsPreloadPrunesStaleCachedAppsUnlessWhitelisted() {
        let store = makeStore()
        store.notificationsEnabled = true
        store.notificationsWhitelistedBundleIDs = ["com.stale.Keep"]
        store.notificationsKnownAppsCache = [
            "com.chat": KnownApp(bundleIdentifier: "com.chat", displayName: "Old Chat", iconCachePath: nil),
            "com.stale.Drop": KnownApp(bundleIdentifier: "com.stale.Drop", displayName: "Drop", iconCachePath: nil),
            "com.stale.Keep": KnownApp(bundleIdentifier: "com.stale.Keep", displayName: "Keep", iconCachePath: nil),
        ]

        let workspace = StubWorkspace()
        workspace.lookups["com.chat"] = (
            URL(fileURLWithPath: "/Applications/Chat.app"),
            "Chat"
        )

        let fake = FakeObserver()
        let plugin = NotificationsPlugin(
            observer: fake,
            settingsStore: store,
            appDirectory: NotificationAppDirectory(workspace: workspace)
        )
        plugin.activate(bus: EventBus())

        fake.reportKnownApps(["com.chat", "com.stale.Drop", "com.stale.Keep"])

        XCTAssertNotNil(store.notificationsKnownAppsCache["com.chat"])
        XCTAssertNil(store.notificationsKnownAppsCache["com.stale.Drop"])
        XCTAssertNotNil(store.notificationsKnownAppsCache["com.stale.Keep"])
        XCTAssertEqual(plugin.diagnostics.knownAppCount, 2)
    }
}
