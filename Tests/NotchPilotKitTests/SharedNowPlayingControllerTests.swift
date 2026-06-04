import XCTest
@testable import NotchPilotKit

final class SharedNowPlayingControllerTests: XCTestCase {
    @MainActor
    func testControllerMirrorsMonitorStateChanges() {
        let monitor = TestSharedNowPlayingMonitor()
        let controller = SharedNowPlayingController(monitor: monitor)

        controller.start()
        monitor.push(.active(Self.snapshot(isPlaying: true)))

        XCTAssertEqual(controller.currentState, .active(Self.snapshot(isPlaying: true)))
    }

    @MainActor
    func testControllerStopsMonitorOnlyAfterAllStartRequestsStop() {
        let monitor = TestSharedNowPlayingMonitor()
        let controller = SharedNowPlayingController(monitor: monitor)

        controller.start()
        controller.start()

        XCTAssertEqual(monitor.startCount, 1)

        controller.stop()

        XCTAssertEqual(monitor.stopCount, 0)

        controller.stop()
        controller.stop()

        XCTAssertEqual(monitor.stopCount, 1)
    }

    @MainActor
    func testControllerDelegatesPlaybackCommands() {
        let monitor = TestSharedNowPlayingMonitor()
        let controller = SharedNowPlayingController(monitor: monitor)

        controller.play()
        controller.pause()
        controller.playPause()
        controller.nextTrack()
        controller.previousTrack()
        controller.seek(to: 42)

        XCTAssertEqual(monitor.playCount, 1)
        XCTAssertEqual(monitor.pauseCount, 1)
        XCTAssertEqual(monitor.playPauseCount, 1)
        XCTAssertEqual(monitor.nextTrackCount, 1)
        XCTAssertEqual(monitor.previousTrackCount, 1)
        XCTAssertEqual(monitor.seekTimes, [42])
    }

    private static func snapshot(isPlaying: Bool) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 1,
            duration: 120,
            playbackRate: 1,
            isPlaying: isPlaying,
            lastUpdated: Date(timeIntervalSince1970: 1)
        )
    }
}

@MainActor
private final class TestSharedNowPlayingMonitor: NowPlayingSessionMonitoring {
    var currentState: MediaPlaybackState = .idle
    var onStateChange: (@MainActor (MediaPlaybackState) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var playPauseCount = 0
    private(set) var nextTrackCount = 0
    private(set) var previousTrackCount = 0
    private(set) var seekTimes: [Double] = []

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
