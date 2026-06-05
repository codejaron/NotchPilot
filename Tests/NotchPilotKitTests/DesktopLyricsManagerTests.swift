import XCTest
@testable import NotchPilotKit

final class DesktopLyricsManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        suiteName = "DesktopLyricsManagerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempHomeURL)
        suiteName = nil
        defaults = nil
        tempHomeURL = nil
    }

    @MainActor
    func testStartDoesNotRequestPlaybackMonitoringWhenDesktopLyricsAreDisabled() {
        let store = makeSettingsStore()
        store.desktopLyricsEnabled = false
        let monitor = TestDesktopLyricsNowPlayingMonitor()
        let controller = SharedNowPlayingController(monitor: monitor)
        let manager = makeManager(nowPlayingController: controller, settingsStore: store)

        manager.start()
        manager.stop()

        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertEqual(monitor.stopCount, 0)
    }

    @MainActor
    func testDesktopLyricsSettingStartsAndStopsPlaybackMonitoringDemand() {
        let store = makeSettingsStore()
        store.desktopLyricsEnabled = false
        let monitor = TestDesktopLyricsNowPlayingMonitor()
        let controller = SharedNowPlayingController(monitor: monitor)
        let manager = makeManager(nowPlayingController: controller, settingsStore: store)

        manager.start()
        store.desktopLyricsEnabled = true

        XCTAssertEqual(monitor.startCount, 1)

        store.desktopLyricsEnabled = false
        manager.stop()

        XCTAssertEqual(monitor.stopCount, 1)
    }

    @MainActor
    func testStartInstallsMouseMonitorSoHoverCanHideLyricsBeforeNextLineTick() {
        let store = makeSettingsStore()
        store.desktopLyricsEnabled = true
        let mouseMonitor = TestDesktopLyricsMouseMonitor()
        let controller = SharedNowPlayingController(monitor: TestDesktopLyricsNowPlayingMonitor())
        let manager = makeManager(
            nowPlayingController: controller,
            settingsStore: store,
            mouseMonitor: mouseMonitor
        )

        manager.start()

        XCTAssertEqual(mouseMonitor.startCallCount, 1)
        XCTAssertNotNil(mouseMonitor.onMouseActivity)

        manager.stop()
    }

    @MainActor
    func testStartDoesNotInstallMouseMonitorWhenDesktopLyricsAreDisabled() {
        let store = makeSettingsStore()
        store.desktopLyricsEnabled = false
        let mouseMonitor = TestDesktopLyricsMouseMonitor()
        let controller = SharedNowPlayingController(monitor: TestDesktopLyricsNowPlayingMonitor())
        let manager = makeManager(
            nowPlayingController: controller,
            settingsStore: store,
            mouseMonitor: mouseMonitor
        )

        manager.start()
        manager.stop()

        XCTAssertEqual(mouseMonitor.startCallCount, 0)
        XCTAssertEqual(mouseMonitor.stopCallCount, 0)
    }

    @MainActor
    func testDesktopLyricsSettingStartsAndStopsMouseMonitorDemand() {
        let store = makeSettingsStore()
        store.desktopLyricsEnabled = false
        let mouseMonitor = TestDesktopLyricsMouseMonitor()
        let controller = SharedNowPlayingController(monitor: TestDesktopLyricsNowPlayingMonitor())
        let manager = makeManager(
            nowPlayingController: controller,
            settingsStore: store,
            mouseMonitor: mouseMonitor
        )

        manager.start()

        XCTAssertEqual(mouseMonitor.startCallCount, 0)

        store.desktopLyricsEnabled = true

        XCTAssertEqual(mouseMonitor.startCallCount, 1)

        store.desktopLyricsEnabled = false
        manager.stop()

        XCTAssertEqual(mouseMonitor.stopCallCount, 1)
    }

    @MainActor
    func testStopRemovesMouseMonitor() {
        let store = makeSettingsStore()
        store.desktopLyricsEnabled = true
        let mouseMonitor = TestDesktopLyricsMouseMonitor()
        let controller = SharedNowPlayingController(monitor: TestDesktopLyricsNowPlayingMonitor())
        let manager = makeManager(
            nowPlayingController: controller,
            settingsStore: store,
            mouseMonitor: mouseMonitor
        )

        manager.start()
        manager.stop()

        XCTAssertEqual(mouseMonitor.stopCallCount, 1)
    }

    @MainActor
    private func makeManager(
        nowPlayingController: SharedNowPlayingController,
        settingsStore: SettingsStore,
        mouseMonitor: DesktopLyricsMouseMonitoring = TestDesktopLyricsMouseMonitor()
    ) -> DesktopLyricsManager {
        let cache = TestDesktopLyricsManagerCache()
        return DesktopLyricsManager(
            nowPlayingController: nowPlayingController,
            settingsStore: settingsStore,
            provider: CachedLyricsProvider(
                cache: cache,
                remoteProvider: TestDesktopLyricsManagerProvider()
            ),
            searchProvider: TestDesktopLyricsManagerSearchProvider(),
            cache: cache,
            ignoredTrackStore: TestDesktopLyricsManagerIgnoredStore(),
            mouseMonitor: mouseMonitor,
            fileManager: .default
        )
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
    }
}

@MainActor
private final class TestDesktopLyricsNowPlayingMonitor: NowPlayingSessionMonitoring {
    var currentState: MediaPlaybackState = .idle
    var onStateChange: (@MainActor (MediaPlaybackState) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func play() {}

    func pause() {}

    func playPause() {}

    func nextTrack() {}

    func previousTrack() {}

    func seek(to time: Double) {}

    func currentPlaybackTime(for source: MediaPlaybackSource) -> TimeInterval? {
        nil
    }
}

@MainActor
private final class TestDesktopLyricsManagerProvider: LyricsProviding {
    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        nil
    }
}

@MainActor
private final class TestDesktopLyricsManagerSearchProvider: LyricsSearching {
    func searchLyrics(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int
    ) async -> [LyricsSearchCandidate] {
        []
    }
}

private final class TestDesktopLyricsManagerCache: LyricsCaching {
    func loadLyrics(for key: LyricsTrackKey) -> TimedLyrics? {
        nil
    }

    func saveLyrics(_ lyrics: TimedLyrics, for key: LyricsTrackKey) throws {}

    func fileURL(for key: LyricsTrackKey) -> URL {
        URL(fileURLWithPath: "/tmp/\(key.cacheFileName)")
    }

    func removeLyrics(for key: LyricsTrackKey) throws {}
}

private final class TestDesktopLyricsManagerIgnoredStore: LyricsTrackIgnoring {
    func contains(_ key: LyricsTrackKey) -> Bool {
        false
    }

    func insert(_ key: LyricsTrackKey) {}

    func remove(_ key: LyricsTrackKey) {}
}

@MainActor
private final class TestDesktopLyricsMouseMonitor: DesktopLyricsMouseMonitoring {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var onMouseActivity: (@MainActor () -> Void)?

    func start(onMouseActivity: @escaping @MainActor () -> Void) {
        startCallCount += 1
        self.onMouseActivity = onMouseActivity
    }

    func stop() {
        stopCallCount += 1
        onMouseActivity = nil
    }
}
