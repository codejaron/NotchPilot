import XCTest
@testable import NotchPilotKit

final class MediaPlaybackPlayerSelectorTests: XCTestCase {
    func testConcretePlayingPlayerStaysSelectedWhenSystemReportsIdle() {
        let date = Date(timeIntervalSince1970: 100)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])

        let selected = selector.update(
            .active(Self.snapshot(
                bundleIdentifier: "com.spotify.client",
                title: "Song",
                artist: "Artist",
                currentTime: 10,
                isPlaying: true,
                lastUpdated: date
            )),
            for: .spotify,
            at: date
        )

        XCTAssertEqual(selected, .active(Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Song",
            artist: "Artist",
            currentTime: 10,
            isPlaying: true,
            lastUpdated: date
        )))

        let reconciled = selector.update(.idle, for: .system, at: date.addingTimeInterval(2))

        guard case let .active(snapshot) = reconciled else {
            return XCTFail("Expected Spotify to remain selected")
        }
        XCTAssertEqual(snapshot.source.bundleIdentifier, "com.spotify.client")
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.currentTime, 12, accuracy: 0.01)
    }

    func testConcretePlayingPlayerIsNotDisplacedByAggregatePlaybackUpdate() {
        let date = Date(timeIntervalSince1970: 200)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
        let spotify = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 20,
            isPlaying: true,
            lastUpdated: date
        )
        let appleMusic = Self.snapshot(
            bundleIdentifier: "com.apple.Music",
            title: "Apple Song",
            artist: "Apple Artist",
            currentTime: 40,
            isPlaying: true,
            lastUpdated: date
        )

        _ = selector.update(.active(spotify), for: .spotify, at: date)
        let selected = selector.update(.active(appleMusic), for: .system, at: date.addingTimeInterval(3))

        guard case let .active(snapshot) = selected else {
            return XCTFail("Expected Spotify to remain selected")
        }
        XCTAssertEqual(snapshot.source.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(snapshot.currentTime, 23, accuracy: 0.01)
    }

    func testHigherPriorityPlayingPlayerDisplacesLowerPriorityPlayingPlayer() {
        let date = Date(timeIntervalSince1970: 250)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
        let chrome = Self.snapshot(
            bundleIdentifier: "com.google.Chrome",
            title: "Live Stream",
            artist: "Chrome",
            currentTime: 40,
            isPlaying: true,
            lastUpdated: date
        )
        let spotify = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 5,
            isPlaying: true,
            lastUpdated: date.addingTimeInterval(2)
        )

        _ = selector.update(.active(chrome), for: .system, at: date)
        let selected = selector.update(.active(spotify), for: .spotify, at: date.addingTimeInterval(2))

        guard case let .active(snapshot) = selected else {
            return XCTFail("Expected Spotify to displace lower-priority system playback")
        }
        XCTAssertEqual(snapshot.source.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(snapshot.title, "Spotify Song")
        XCTAssertEqual(snapshot.currentTime, 5, accuracy: 0.01)
    }

    func testAggregatePlayerIsUsedWhenConcretePlayerStops() {
        let date = Date(timeIntervalSince1970: 300)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
        let spotify = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 20,
            isPlaying: true,
            lastUpdated: date
        )
        let appleMusic = Self.snapshot(
            bundleIdentifier: "com.apple.Music",
            title: "Apple Song",
            artist: "Apple Artist",
            currentTime: 40,
            isPlaying: true,
            lastUpdated: date
        )

        _ = selector.update(.active(spotify), for: .spotify, at: date)
        _ = selector.update(.active(appleMusic), for: .system, at: date)
        let selected = selector.update(.idle, for: .spotify, at: date.addingTimeInterval(2))

        XCTAssertEqual(selected, .active(appleMusic.replacingCurrentTime(42, at: date.addingTimeInterval(2))))
    }

    func testAggregateSpotifyPlaybackDoesNotOverrideConcreteSpotifyPause() {
        let date = Date(timeIntervalSince1970: 350)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
        let spotifyPlaying = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 20,
            isPlaying: true,
            lastUpdated: date
        )
        let staleAggregateSpotify = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 20,
            isPlaying: true,
            lastUpdated: date
        )
        let spotifyPaused = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 22,
            playbackRate: 0,
            isPlaying: false,
            lastUpdated: date.addingTimeInterval(2)
        )

        _ = selector.update(.active(spotifyPlaying), for: .spotify, at: date)
        _ = selector.update(.active(staleAggregateSpotify), for: .system, at: date.addingTimeInterval(1))
        let selected = selector.update(.active(spotifyPaused), for: .spotify, at: date.addingTimeInterval(2))

        XCTAssertEqual(selected, .active(spotifyPaused))
    }

    func testAggregateSpotifyPlaybackDoesNotReviveStoppedConcreteSpotify() {
        let date = Date(timeIntervalSince1970: 360)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
        let spotifyPlaying = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 20,
            isPlaying: true,
            lastUpdated: date
        )
        let staleAggregateSpotify = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 20,
            isPlaying: true,
            lastUpdated: date
        )

        _ = selector.update(.active(spotifyPlaying), for: .spotify, at: date)
        _ = selector.update(.active(staleAggregateSpotify), for: .system, at: date.addingTimeInterval(1))
        let selected = selector.update(.idle, for: .spotify, at: date.addingTimeInterval(2))

        XCTAssertEqual(selected, .idle)
    }

    func testConcretePausedPlayerWinsOverAggregatePausedPlayerWhenNothingIsPlaying() {
        let date = Date(timeIntervalSince1970: 400)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
        let appleMusic = Self.snapshot(
            bundleIdentifier: "com.apple.Music",
            title: "Apple Song",
            artist: "Apple Artist",
            currentTime: 40,
            playbackRate: 0,
            isPlaying: false,
            lastUpdated: date
        )
        let spotify = Self.snapshot(
            bundleIdentifier: "com.spotify.client",
            title: "Spotify Song",
            artist: "Spotify Artist",
            currentTime: 20,
            playbackRate: 0,
            isPlaying: false,
            lastUpdated: date
        )

        _ = selector.update(.active(appleMusic), for: .system, at: date)
        let selected = selector.update(.active(spotify), for: .spotify, at: date)

        XCTAssertEqual(selected, .active(spotify))
    }

    func testStoppedConcretePlayerDoesNotClearAggregatePlayingPlayer() {
        let date = Date(timeIntervalSince1970: 500)
        var selector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
        let appleMusic = Self.snapshot(
            bundleIdentifier: "com.apple.Music",
            title: "Apple Song",
            artist: "Apple Artist",
            currentTime: 40,
            isPlaying: true,
            lastUpdated: date
        )

        _ = selector.update(.active(appleMusic), for: .system, at: date)
        let selected = selector.update(.idle, for: .spotify, at: date)

        XCTAssertEqual(selected, .active(appleMusic))
    }

    private static func snapshot(
        bundleIdentifier: String,
        title: String,
        artist: String,
        currentTime: TimeInterval,
        playbackRate: Double = 1,
        isPlaying: Bool,
        lastUpdated: Date
    ) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: .fromBundleIdentifier(bundleIdentifier),
            title: title,
            artist: artist,
            album: "Album",
            artworkData: nil,
            currentTime: currentTime,
            duration: 200,
            playbackRate: playbackRate,
            isPlaying: isPlaying,
            lastUpdated: lastUpdated
        )
    }
}
