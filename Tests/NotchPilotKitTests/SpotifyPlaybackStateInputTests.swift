import XCTest
@testable import NotchPilotKit

@MainActor
final class SpotifyPlaybackStateInputTests: XCTestCase {
    func testSpotifyPlayerDoesNotRunSnapshotScriptWhenSpotifyIsNotRunning() async {
        var didRunScript = false
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: { _ in
                didRunScript = true
                return nil
            },
            commandScriptRunner: { _ in false },
            playbackTimeScriptRunner: { _ in nil },
            isSpotifyRunning: { false }
        )

        let snapshot = await player.currentSpotifyPlaybackSnapshot(at: Date(timeIntervalSince1970: 10))

        XCTAssertNil(snapshot)
        XCTAssertFalse(didRunScript)
    }

    func testSpotifyPlayerReadsSnapshotWhenSpotifyIsRunning() async {
        let date = Date(timeIntervalSince1970: 20)
        let separator = "\u{1f}"
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: { _ in
                [
                    "playing",
                    "12.5",
                    "180",
                    "Song",
                    "Artist",
                    "Album",
                ].joined(separator: separator)
            },
            commandScriptRunner: { _ in false },
            playbackTimeScriptRunner: { _ in nil },
            isSpotifyRunning: { true }
        )

        let snapshot = await player.currentSpotifyPlaybackSnapshot(at: date)

        XCTAssertEqual(snapshot?.source.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(snapshot?.title, "Song")
        XCTAssertEqual(snapshot?.artist, "Artist")
        XCTAssertEqual(snapshot?.currentTime, 12.5)
        XCTAssertEqual(snapshot?.duration, 180)
        XCTAssertEqual(snapshot?.isPlaying, true)
        XCTAssertEqual(snapshot?.lastUpdated, date)
    }

    func testSpotifyPlayerReadsArtworkFromSnapshotScript() async {
        let separator = "\u{1f}"
        let artwork = Data([1, 2, 3])
        var requestedURLs: [URL] = []
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: { _ in
                [
                    "playing",
                    "12.5",
                    "180",
                    "Song",
                    "Artist",
                    "Album",
                    "https://i.scdn.co/image/abc",
                ].joined(separator: separator)
            },
            commandScriptRunner: { _ in false },
            playbackTimeScriptRunner: { _ in nil },
            artworkDataLoader: { url in
                await Task.yield()
                requestedURLs.append(url)
                return artwork
            },
            isSpotifyRunning: { true }
        )

        let snapshot = await player.currentSpotifyPlaybackSnapshot(at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(snapshot?.artworkData, artwork)
        XCTAssertEqual(requestedURLs, [URL(string: "https://i.scdn.co/image/abc")])
    }

    func testSpotifyPlayerRunsPlaybackCommandsThroughSpotifyScript() {
        var scripts: [String] = []
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: { _ in nil },
            commandScriptRunner: {
                scripts.append($0)
                return true
            },
            playbackTimeScriptRunner: { _ in nil },
            isSpotifyRunning: { true }
        )

        XCTAssertTrue(player.perform(.play))
        XCTAssertTrue(player.perform(.pause))
        XCTAssertTrue(player.perform(.togglePlayPause))
        XCTAssertTrue(player.perform(.nextTrack))
        XCTAssertTrue(player.perform(.previousTrack))
        XCTAssertTrue(player.perform(.seek(42.5)))

        XCTAssertEqual(scripts, [
            "tell application \"Spotify\" to play",
            "tell application \"Spotify\" to pause",
            "tell application \"Spotify\" to playpause",
            "tell application \"Spotify\" to next track",
            "tell application \"Spotify\" to previous track",
            "tell application \"Spotify\" to set player position to 42.5",
        ])
    }

    func testSpotifySnapshotScriptReturnsPositionInSeconds() async {
        var script = ""
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: {
                script = $0
                return nil
            },
            commandScriptRunner: { _ in false },
            playbackTimeScriptRunner: { _ in nil },
            isSpotifyRunning: { true }
        )

        _ = await player.currentSpotifyPlaybackSnapshot(at: Date(timeIntervalSince1970: 20))

        XCTAssertTrue(script.contains("set trackPosition to player position"))
        XCTAssertTrue(script.contains("trackPosition & sep"))
        XCTAssertFalse(script.contains("trackPositionMilliseconds"))
    }

    func testSpotifyPlayerDoesNotRunPlaybackCommandWhenSpotifyIsNotRunning() {
        var didRunScript = false
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: { _ in nil },
            commandScriptRunner: { _ in
                didRunScript = true
                return true
            },
            playbackTimeScriptRunner: { _ in nil },
            isSpotifyRunning: { false }
        )

        XCTAssertFalse(player.perform(.nextTrack))
        XCTAssertFalse(didRunScript)
    }

    @MainActor
    func testSpotifyPlayerReadsPlaybackTimeThroughSpotifyScript() async {
        var scripts: [String] = []
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: { _ in nil },
            commandScriptRunner: { _ in false },
            playbackTimeScriptRunner: {
                scripts.append($0)
                return 23.75
            },
            isSpotifyRunning: { true }
        )

        let playbackTime = await player.currentPlaybackTime()
        XCTAssertEqual(playbackTime, 23.75)
        XCTAssertEqual(scripts, ["tell application \"Spotify\" to return player position"])
    }

    @MainActor
    func testSpotifyPlayerCachesRecentPlaybackTimeRead() async {
        var scripts: [String] = []
        let player = AppleScriptSpotifyPlaybackPlayer(
            snapshotScriptRunner: { _ in nil },
            commandScriptRunner: { _ in false },
            playbackTimeScriptRunner: {
                scripts.append($0)
                return 23.75
            },
            isSpotifyRunning: { true },
            playbackTimeCacheDuration: 1,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let first = await player.currentPlaybackTime()
        let second = await player.currentPlaybackTime()

        XCTAssertEqual(first, 23.75)
        XCTAssertEqual(second, 23.75)
        XCTAssertEqual(scripts, ["tell application \"Spotify\" to return player position"])
    }

    func testSpotifyPlaybackNoticeBuildsPlayingSnapshot() async {
        let date = Date(timeIntervalSince1970: 100)
        let state = await SpotifyPlaybackNotice.state(
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

    func testSpotifyPlaybackNoticeParsesTrackID() {
        let payload = SpotifyPlaybackNotice.payload(
            from: [
                "Player State": "Playing",
                "Playback Position": 42.5,
                "Track ID": "spotify:track:abc",
            ]
        )

        XCTAssertEqual(payload?.trackID, "spotify:track:abc")
    }

    func testSpotifyPlaybackNoticeLoadsArtworkURL() async {
        let artwork = Data([4, 5, 6])
        var requestedURLs: [URL] = []
        let state = await SpotifyPlaybackNotice.state(
            from: [
                "Player State": "Playing",
                "Playback Position": 42.5,
                "Duration": 213_000,
                "Name": "Song",
                "Artist": "Artist",
                "Album": "Album",
                "Artwork URL": "https://i.scdn.co/image/notice",
            ],
            fallback: nil,
            artworkDataLoader: { url in
                await Task.yield()
                requestedURLs.append(url)
                return artwork
            },
            at: Date(timeIntervalSince1970: 100)
        )

        guard case let .active(snapshot) = state else {
            return XCTFail("Expected active Spotify snapshot")
        }

        XCTAssertEqual(snapshot.artworkData, artwork)
        XCTAssertEqual(requestedURLs, [URL(string: "https://i.scdn.co/image/notice")])
    }

    func testSpotifyPlaybackNoticeDoesNotReuseFallbackArtworkForDifferentTrack() async {
        let fallback = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Old Song",
            artist: "Old Artist",
            album: "Old Album",
            artworkData: Data([9, 9, 9]),
            currentTime: 12,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 90)
        )

        let state = await SpotifyPlaybackNotice.state(
            from: [
                "Player State": "Playing",
                "Playback Position": 1,
                "Duration": 213_000,
                "Name": "New Song",
                "Artist": "New Artist",
                "Album": "New Album",
            ],
            fallback: fallback,
            artworkDataLoader: { _ in
                XCTFail("Missing artwork URL should not call loader")
                return nil
            },
            at: Date(timeIntervalSince1970: 100)
        )

        guard case let .active(snapshot) = state else {
            return XCTFail("Expected active Spotify snapshot")
        }

        XCTAssertEqual(snapshot.title, "New Song")
        XCTAssertNil(snapshot.artworkData)
    }

    func testSpotifyScriptResultBuildsInitialPlayingSnapshot() {
        let date = Date(timeIntervalSince1970: 250)
        let separator = "\u{1f}"
        let result = [
            "playing",
            "31.25",
            "188",
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
