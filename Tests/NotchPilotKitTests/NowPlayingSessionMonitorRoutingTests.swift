import XCTest
@testable import NotchPilotKit

@MainActor
final class NowPlayingSessionMonitorRoutingTests: XCTestCase {
    func testReadsSpotifyPlaybackTimeFromSpotifyPlayer() async {
        let spotifyPlayer = TestSpotifyPlaybackPlayer(playbackTime: 44.5)
        let playbackTimeProvider = RecordingPlaybackTimeProvider(playbackTime: 12)
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: playbackTimeProvider,
            spotifyPlayer: spotifyPlayer
        )

        let playbackTime = await monitor.currentPlaybackTime(for: .fromBundleIdentifier("com.spotify.client"))

        XCTAssertEqual(playbackTime, 44.5)
        XCTAssertEqual(spotifyPlayer.playbackTimeRequestCount, 1)
        XCTAssertEqual(playbackTimeProvider.sources, [])
    }

    func testReadsNonSpotifyPlaybackTimeFromSystemProvider() async {
        let spotifyPlayer = TestSpotifyPlaybackPlayer(playbackTime: 44.5)
        let playbackTimeProvider = RecordingPlaybackTimeProvider(playbackTime: 12)
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: playbackTimeProvider,
            spotifyPlayer: spotifyPlayer
        )
        let source = MediaPlaybackSource.fromBundleIdentifier("com.apple.Music")

        let playbackTime = await monitor.currentPlaybackTime(for: source)

        XCTAssertEqual(playbackTime, 12)
        XCTAssertEqual(spotifyPlayer.playbackTimeRequestCount, 0)
        XCTAssertEqual(playbackTimeProvider.sources, [source])
    }

    func testSpotifyTrackIDChangeRefreshesCompleteSnapshot() async {
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Complete Song",
            artist: "Complete Artist",
            album: "Complete Album",
            artworkData: Data([7, 8, 9]),
            currentTime: 3,
            duration: 180,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 10)
        )
        let spotifyPlayer = TestSpotifyPlaybackPlayer(
            playbackTime: nil,
            snapshots: [snapshot]
        )
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: RecordingPlaybackTimeProvider(playbackTime: nil),
            spotifyPlayer: spotifyPlayer
        )
        let payload = SpotifyPlaybackNotice.Payload(
            playback: .playing,
            title: "Notification Song",
            artist: "Notification Artist",
            album: "Notification Album",
            position: 1,
            duration: 180_000,
            artworkURL: nil,
            trackID: "spotify:track:new"
        )

        await monitor.applySpotifyPlaybackPayload(payload)

        XCTAssertEqual(spotifyPlayer.snapshotRequestCount, 1)
        guard case let .active(current) = monitor.currentState else {
            return XCTFail("Expected active Spotify snapshot")
        }
        XCTAssertEqual(current.title, "Complete Song")
        XCTAssertEqual(current.artist, "Complete Artist")
        XCTAssertEqual(current.artworkData, Data([7, 8, 9]))
    }

    func testSpotifySameTrackIDDoesNotKeepRefreshingCompleteSnapshot() async {
        let spotifyPlayer = TestSpotifyPlaybackPlayer(
            playbackTime: nil,
            snapshots: [
                MediaPlaybackSnapshot(
                    source: .fromBundleIdentifier("com.spotify.client"),
                    title: "Complete Song",
                    artist: "Complete Artist",
                    album: "Complete Album",
                    artworkData: Data([7, 8, 9]),
                    currentTime: 3,
                    duration: 180,
                    playbackRate: 1,
                    isPlaying: true,
                    lastUpdated: Date(timeIntervalSince1970: 10)
                ),
            ]
        )
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: RecordingPlaybackTimeProvider(playbackTime: nil),
            spotifyPlayer: spotifyPlayer
        )
        let payload = SpotifyPlaybackNotice.Payload(
            playback: .playing,
            title: "Notification Song",
            artist: "Notification Artist",
            album: "Notification Album",
            position: 1,
            duration: 180_000,
            artworkURL: nil,
            trackID: "spotify:track:new"
        )

        await monitor.applySpotifyPlaybackPayload(payload)
        await monitor.applySpotifyPlaybackPayload(payload)

        XCTAssertEqual(spotifyPlayer.snapshotRequestCount, 1)
    }

    func testSpotifyPausedPayloadIsNotOverriddenByCompleteSnapshotRefresh() async {
        let stalePlayingSnapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Stale Playing Song",
            artist: "Stale Artist",
            album: "Stale Album",
            artworkData: Data([7, 8, 9]),
            currentTime: 30,
            duration: 180,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 10)
        )
        let spotifyPlayer = TestSpotifyPlaybackPlayer(
            playbackTime: nil,
            snapshots: [stalePlayingSnapshot]
        )
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: RecordingPlaybackTimeProvider(playbackTime: nil),
            spotifyPlayer: spotifyPlayer
        )
        let payload = SpotifyPlaybackNotice.Payload(
            playback: .paused,
            title: "Paused Song",
            artist: "Paused Artist",
            album: "Paused Album",
            position: 12,
            duration: 180_000,
            artworkURL: nil,
            trackID: "spotify:track:paused"
        )

        await monitor.applySpotifyPlaybackPayload(payload)

        XCTAssertEqual(spotifyPlayer.snapshotRequestCount, 0)
        guard case let .active(current) = monitor.currentState else {
            return XCTFail("Expected paused Spotify snapshot")
        }
        XCTAssertEqual(current.title, "Paused Song")
        XCTAssertFalse(current.isPlaying)
        XCTAssertEqual(current.playbackRate, 0)
    }

    func testSpotifyStoppedPayloadClearsPlaybackWithoutCompleteSnapshotRefresh() async {
        let stalePlayingSnapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Stale Playing Song",
            artist: "Stale Artist",
            album: "Stale Album",
            artworkData: Data([7, 8, 9]),
            currentTime: 30,
            duration: 180,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 10)
        )
        let spotifyPlayer = TestSpotifyPlaybackPlayer(
            playbackTime: nil,
            snapshots: [stalePlayingSnapshot]
        )
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: RecordingPlaybackTimeProvider(playbackTime: nil),
            spotifyPlayer: spotifyPlayer
        )
        let payload = SpotifyPlaybackNotice.Payload(
            playback: .stopped,
            title: nil,
            artist: nil,
            album: nil,
            position: nil,
            duration: nil,
            artworkURL: nil,
            trackID: "spotify:track:stopped"
        )

        await monitor.applySpotifyPlaybackPayload(payload)

        XCTAssertEqual(spotifyPlayer.snapshotRequestCount, 0)
        XCTAssertEqual(monitor.currentState, .idle)
    }

    func testSpotifyPausedPayloadDoesNotMarkTrackAsCompletelyRefreshed() async {
        let completeSnapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Complete Song",
            artist: "Complete Artist",
            album: "Complete Album",
            artworkData: Data([7, 8, 9]),
            currentTime: 14,
            duration: 180,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 10)
        )
        let spotifyPlayer = TestSpotifyPlaybackPlayer(
            playbackTime: nil,
            snapshots: [completeSnapshot]
        )
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: RecordingPlaybackTimeProvider(playbackTime: nil),
            spotifyPlayer: spotifyPlayer
        )
        let pausedPayload = SpotifyPlaybackNotice.Payload(
            playback: .paused,
            title: "Paused Song",
            artist: "Paused Artist",
            album: "Paused Album",
            position: 12,
            duration: 180_000,
            artworkURL: nil,
            trackID: "spotify:track:same"
        )
        let playingPayload = SpotifyPlaybackNotice.Payload(
            playback: .playing,
            title: "Playing Song",
            artist: "Playing Artist",
            album: "Playing Album",
            position: 13,
            duration: 180_000,
            artworkURL: nil,
            trackID: "spotify:track:same"
        )

        await monitor.applySpotifyPlaybackPayload(pausedPayload)
        await monitor.applySpotifyPlaybackPayload(playingPayload)

        XCTAssertEqual(spotifyPlayer.snapshotRequestCount, 1)
        guard case let .active(current) = monitor.currentState else {
            return XCTFail("Expected active Spotify snapshot")
        }
        XCTAssertEqual(current.title, "Complete Song")
        XCTAssertEqual(current.artworkData, Data([7, 8, 9]))
    }

    func testPlaybackTimeReconciliationReanchorsSpotifySeek() async {
        let spotifyPlayer = TestSpotifyPlaybackPlayer(playbackTime: 75)
        let monitor = NowPlayingSessionMonitor(
            playbackTimeProvider: RecordingPlaybackTimeProvider(playbackTime: nil),
            spotifyPlayer: spotifyPlayer
        )
        let initialPayload = SpotifyPlaybackNotice.Payload(
            playback: .playing,
            title: "Song",
            artist: "Artist",
            album: "Album",
            position: 10,
            duration: 180,
            artworkURL: nil,
            trackID: "spotify:track:song"
        )

        await monitor.applySpotifyPlaybackPayload(initialPayload)
        await monitor.reconcilePlaybackTime(at: Date(timeIntervalSince1970: 11))

        XCTAssertEqual(spotifyPlayer.playbackTimeRequestCount, 1)
        guard case let .active(current) = monitor.currentState else {
            return XCTFail("Expected active Spotify snapshot")
        }
        XCTAssertEqual(current.currentTime, 75)
    }
}

private final class TestSpotifyPlaybackPlayer: SpotifyPlaybackPlayerOperating {
    private let playbackTime: TimeInterval?
    private var snapshots: [MediaPlaybackSnapshot?]
    private(set) var playbackTimeRequestCount = 0
    private(set) var snapshotRequestCount = 0
    private(set) var commands: [MediaPlaybackCommand] = []

    init(playbackTime: TimeInterval?, snapshots: [MediaPlaybackSnapshot?] = []) {
        self.playbackTime = playbackTime
        self.snapshots = snapshots
    }

    func currentSpotifyPlaybackSnapshot(at date: Date) async -> MediaPlaybackSnapshot? {
        snapshotRequestCount += 1
        await Task.yield()
        return snapshots.isEmpty ? nil : snapshots.removeFirst()
    }

    func currentPlaybackTime() async -> TimeInterval? {
        playbackTimeRequestCount += 1
        return playbackTime
    }

    func perform(_ command: MediaPlaybackCommand) -> Bool {
        commands.append(command)
        return true
    }
}

private final class RecordingPlaybackTimeProvider: PlaybackTimeProviding {
    private let playbackTime: TimeInterval?
    private(set) var sources: [MediaPlaybackSource] = []

    init(playbackTime: TimeInterval?) {
        self.playbackTime = playbackTime
    }

    func currentPlaybackTime(for source: MediaPlaybackSource) async -> TimeInterval? {
        sources.append(source)
        return playbackTime
    }
}
