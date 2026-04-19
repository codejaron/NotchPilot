import SwiftUI
import XCTest
@testable import NotchPilotKit

final class MediaPlaybackPluginTests: XCTestCase {
    private static let previewContext = NotchContext(
        screenID: "test-screen",
        notchState: .previewClosed,
        notchGeometry: NotchGeometry(
            compactSize: CGSize(width: 185, height: 32),
            expandedSize: CGSize(width: 520, height: 320)
        ),
        isPrimaryScreen: true
    )

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        suiteName = "MediaPlaybackPluginTests.\(UUID().uuidString)"
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
    func testPluginMetadataMatchesMediaEntry() {
        let plugin = MediaPlaybackPlugin(
            monitor: TestNowPlayingSessionMonitor(),
            settingsStore: makeSettingsStore()
        )

        XCTAssertEqual(plugin.id, "media-playback")
        XCTAssertEqual(plugin.title, "Media")
        XCTAssertEqual(plugin.iconSystemName, "music.note")
        XCTAssertEqual(plugin.dockOrder, 120)
        XCTAssertTrue(plugin.isEnabled)
    }

    @MainActor
    func testPluginReflectsMediaAvailabilitySetting() {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = false
        let plugin = MediaPlaybackPlugin(
            monitor: TestNowPlayingSessionMonitor(initialState: Self.activeState(isPlaying: true)),
            settingsStore: store
        )

        XCTAssertFalse(plugin.isEnabled)
        XCTAssertNil(plugin.preview(context: Self.previewContext))

        store.mediaPlaybackEnabled = true

        XCTAssertTrue(plugin.isEnabled)
    }

    @MainActor
    func testActivePlaybackRequestsPersistentSneakPreviewWhenEnabled() {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.mediaPlaybackSneakPreviewEnabled = true
        let monitor = TestNowPlayingSessionMonitor()
        let plugin = MediaPlaybackPlugin(monitor: monitor, settingsStore: store)
        let bus = EventBus()
        let recorder = MediaPlaybackEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        monitor.push(Self.activeState(isPlaying: true))

        guard case let .sneakPeekRequested(request)? = recorder.events.first else {
            XCTFail("Expected media sneak peek request")
            bus.unsubscribe(token)
            return
        }

        XCTAssertEqual(request.pluginID, plugin.id)
        XCTAssertEqual(request.priority, 700)
        XCTAssertEqual(request.target, .activeScreen)
        XCTAssertFalse(request.isInteractive)
        XCTAssertNil(request.autoDismissAfter)
        XCTAssertNotNil(plugin.preview(context: Self.previewContext))

        bus.unsubscribe(token)
    }

    @MainActor
    func testSneakPreviewWidthReservesCameraClearanceBetweenVisuals() throws {
        let monitor = TestNowPlayingSessionMonitor(initialState: Self.activeState(isPlaying: true))
        let plugin = MediaPlaybackPlugin(
            monitor: monitor,
            settingsStore: makeSettingsStore()
        )

        let preview = try XCTUnwrap(plugin.preview(context: Self.previewContext))

        XCTAssertEqual(
            preview.width,
            MediaPlaybackCompactPreviewLayout.preferredWidth(
                forCompactWidth: Self.previewContext.notchGeometry.compactSize.width
            ),
            accuracy: 0.01
        )
    }

    @MainActor
    func testPausedPlaybackUsesAutoDismissSneakPreview() {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.mediaPlaybackSneakPreviewEnabled = true
        let monitor = TestNowPlayingSessionMonitor()
        let plugin = MediaPlaybackPlugin(monitor: monitor, settingsStore: store)
        let bus = EventBus()
        let recorder = MediaPlaybackEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        monitor.push(Self.activeState(isPlaying: false))

        guard case let .sneakPeekRequested(request)? = recorder.events.first else {
            XCTFail("Expected paused media sneak peek request")
            bus.unsubscribe(token)
            return
        }

        XCTAssertEqual(try XCTUnwrap(request.autoDismissAfter), 10, accuracy: 0.01)

        bus.unsubscribe(token)
    }

    @MainActor
    func testReenablingGlobalActivitySneaksReissuesActivePlaybackSneakPreview() {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.mediaPlaybackSneakPreviewEnabled = true
        let monitor = TestNowPlayingSessionMonitor()
        let plugin = MediaPlaybackPlugin(monitor: monitor, settingsStore: store)
        let bus = EventBus()
        let recorder = MediaPlaybackEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        monitor.push(Self.activeState(isPlaying: true))

        guard case let .sneakPeekRequested(initialRequest)? = recorder.events.first else {
            XCTFail("Expected initial media sneak peek request")
            bus.unsubscribe(token)
            return
        }

        store.activitySneakPreviewsHidden = true

        guard case let .dismissSneakPeek(hiddenRequestID, _)? = recorder.events.last else {
            XCTFail("Expected media sneak peek dismissal when hiding activity sneaks")
            bus.unsubscribe(token)
            return
        }
        XCTAssertEqual(hiddenRequestID, initialRequest.id)

        store.activitySneakPreviewsHidden = false

        guard case let .sneakPeekRequested(restoredRequest)? = recorder.events.last else {
            XCTFail("Expected media sneak peek request after showing activity sneaks")
            bus.unsubscribe(token)
            return
        }
        XCTAssertEqual(restoredRequest.pluginID, plugin.id)
        XCTAssertNotEqual(restoredRequest.id, initialRequest.id)

        bus.unsubscribe(token)
    }

    @MainActor
    func testIdleStateDismissesExistingSneakPreview() {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.mediaPlaybackSneakPreviewEnabled = true
        let monitor = TestNowPlayingSessionMonitor()
        let plugin = MediaPlaybackPlugin(monitor: monitor, settingsStore: store)
        let bus = EventBus()
        let recorder = MediaPlaybackEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        monitor.push(Self.activeState(isPlaying: true))
        monitor.push(.idle)

        guard case .sneakPeekRequested = recorder.events.first else {
            XCTFail("Expected initial sneak peek request")
            bus.unsubscribe(token)
            return
        }
        guard case let .dismissSneakPeek(requestID, target)? = recorder.events.last else {
            XCTFail("Expected media sneak peek dismissal")
            bus.unsubscribe(token)
            return
        }

        XCTAssertNotNil(requestID)
        XCTAssertEqual(target, .allScreens)
        XCTAssertNil(plugin.preview(context: Self.previewContext))

        bus.unsubscribe(token)
    }

    @MainActor
    func testDeactivateStopsMonitorAndDismissesSneakPreview() {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.mediaPlaybackSneakPreviewEnabled = true
        let monitor = TestNowPlayingSessionMonitor()
        let plugin = MediaPlaybackPlugin(monitor: monitor, settingsStore: store)
        let bus = EventBus()
        let recorder = MediaPlaybackEventRecorder()

        let token = bus.subscribe { event in
            recorder.events.append(event)
        }

        plugin.activate(bus: bus)
        monitor.push(Self.activeState(isPlaying: true))
        plugin.deactivate()

        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(monitor.stopCount, 1)
        guard case .dismissSneakPeek = recorder.events.last else {
            XCTFail("Expected media sneak peek dismissal on deactivate")
            bus.unsubscribe(token)
            return
        }

        bus.unsubscribe(token)
    }

    @MainActor
    func testPrimaryPlaybackActionPausesWhenCurrentlyPlaying() {
        let monitor = TestNowPlayingSessionMonitor(initialState: Self.activeState(isPlaying: true))
        let plugin = MediaPlaybackPlugin(
            monitor: monitor,
            settingsStore: makeSettingsStore()
        )

        plugin.performPrimaryPlaybackActionForTesting()

        XCTAssertEqual(monitor.pauseCount, 1)
        XCTAssertEqual(monitor.playCount, 0)
        XCTAssertEqual(monitor.playPauseCount, 0)
    }

    @MainActor
    func testPrimaryPlaybackActionPlaysWhenCurrentlyPaused() {
        let monitor = TestNowPlayingSessionMonitor(initialState: Self.activeState(isPlaying: false))
        let plugin = MediaPlaybackPlugin(
            monitor: monitor,
            settingsStore: makeSettingsStore()
        )

        plugin.performPrimaryPlaybackActionForTesting()

        XCTAssertEqual(monitor.playCount, 1)
        XCTAssertEqual(monitor.pauseCount, 0)
        XCTAssertEqual(monitor.playPauseCount, 0)
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
    }

    private static func activeState(isPlaying: Bool) -> MediaPlaybackState {
        .active(
            MediaPlaybackSnapshot(
                source: .fromBundleIdentifier("com.spotify.client"),
                title: "As If It's Your Last",
                artist: "BLACKPINK",
                album: "Single",
                artworkData: nil,
                currentTime: 1,
                duration: 213,
                playbackRate: 1,
                isPlaying: isPlaying,
                lastUpdated: Date(timeIntervalSince1970: 1)
            )
        )
    }
}

@MainActor
private final class TestNowPlayingSessionMonitor: NowPlayingSessionMonitoring {
    var currentState: MediaPlaybackState
    var onStateChange: (@MainActor (MediaPlaybackState) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var playPauseCount = 0
    private(set) var nextTrackCount = 0
    private(set) var previousTrackCount = 0
    private(set) var seekTimes: [Double] = []

    init(initialState: MediaPlaybackState = .idle) {
        self.currentState = initialState
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func play() {
        playCount += 1
    }

    func pause() {
        pauseCount += 1
    }

    func playPause() {
        playPauseCount += 1
    }

    func nextTrack() {
        nextTrackCount += 1
    }

    func previousTrack() {
        previousTrackCount += 1
    }

    func seek(to time: Double) {
        seekTimes.append(time)
    }

    func push(_ state: MediaPlaybackState) {
        currentState = state
        onStateChange?(state)
    }
}

@MainActor
private final class MediaPlaybackEventRecorder {
    var events: [NotchEvent] = []
}
