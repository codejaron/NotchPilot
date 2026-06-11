import XCTest
@testable import NotchPilotKit

final class SpotifyPlaybackStateInputTests: XCTestCase {
    func testSpotifyProviderDoesNotRunScriptWhenSpotifyIsNotRunning() {
        var didRunScript = false
        let provider = AppleScriptSpotifyPlaybackSnapshotProvider(
            scriptRunner: { _ in
                didRunScript = true
                return nil
            },
            isSpotifyRunning: { false }
        )

        XCTAssertNil(provider.currentSpotifyPlaybackSnapshot(at: Date(timeIntervalSince1970: 10)))
        XCTAssertFalse(didRunScript)
    }

    func testSpotifyProviderReadsSnapshotWhenSpotifyIsRunning() {
        let date = Date(timeIntervalSince1970: 20)
        let separator = "\u{1f}"
        let provider = AppleScriptSpotifyPlaybackSnapshotProvider(
            scriptRunner: { _ in
                [
                    "playing",
                    "12",
                    "180000",
                    "Song",
                    "Artist",
                    "Album",
                ].joined(separator: separator)
            },
            isSpotifyRunning: { true }
        )

        let snapshot = provider.currentSpotifyPlaybackSnapshot(at: date)

        XCTAssertEqual(snapshot?.source.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(snapshot?.title, "Song")
        XCTAssertEqual(snapshot?.artist, "Artist")
        XCTAssertEqual(snapshot?.currentTime, 12)
        XCTAssertEqual(snapshot?.duration, 180)
        XCTAssertEqual(snapshot?.isPlaying, true)
        XCTAssertEqual(snapshot?.lastUpdated, date)
    }

    func testSpotifyPlaybackNoticeBuildsPlayingSnapshot() {
        let date = Date(timeIntervalSince1970: 100)
        let state = SpotifyPlaybackNotice.state(
            from: [
                "Player State": "Playing",
                "Playback Position": 42.5,
                "Duration": 213_000,
                "Name": "Song",
                "Artist": "Artist",
                "Album": "Album",
            ],
            fallback: nil,
            at: date
        )

        guard case let .active(snapshot) = state else {
            return XCTFail("Expected active Spotify snapshot")
        }

        XCTAssertEqual(snapshot.source.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(snapshot.title, "Song")
        XCTAssertEqual(snapshot.artist, "Artist")
        XCTAssertEqual(snapshot.album, "Album")
        XCTAssertEqual(snapshot.currentTime, 42.5)
        XCTAssertEqual(snapshot.duration, 213)
        XCTAssertEqual(snapshot.playbackRate, 1)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.lastUpdated, date)
    }

    func testSpotifyScriptResultBuildsInitialPlayingSnapshot() {
        let date = Date(timeIntervalSince1970: 250)
        let separator = "\u{1f}"
        let result = [
            "playing",
            "31.25",
            "188000",
            "Song",
            "Artist",
            "Album",
        ].joined(separator: separator)

        let snapshot = SpotifyPlaybackScriptResult.snapshot(from: result, at: date)

        XCTAssertEqual(snapshot?.source.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(snapshot?.title, "Song")
        XCTAssertEqual(snapshot?.artist, "Artist")
        XCTAssertEqual(snapshot?.currentTime, 31.25)
        XCTAssertEqual(snapshot?.duration, 188)
        XCTAssertEqual(snapshot?.playbackRate, 1)
        XCTAssertEqual(snapshot?.isPlaying, true)
        XCTAssertEqual(snapshot?.lastUpdated, date)
    }
}
