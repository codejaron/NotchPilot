import XCTest
@testable import NotchPilotKit

final class MediaPlaybackModelsTests: XCTestCase {
    func testSourceDisplayNameResolvesSpotifyBundleIdentifier() {
        let source = MediaPlaybackSource.fromBundleIdentifier("com.spotify.client")

        XCTAssertEqual(source.displayName, "Spotify")
        XCTAssertEqual(source.systemImageName, "music.note")
    }

    func testPayloadBundleIdentifierPrefersParentApplicationBundleIdentifier() {
        let payload = NowPlayingSessionPayload(
            title: "Track",
            artist: "Artist",
            album: "Album",
            duration: 120,
            elapsedTime: 15,
            artworkData: nil,
            timestamp: Date(timeIntervalSince1970: 10),
            playbackRate: 1,
            isPlaying: true,
            parentApplicationBundleIdentifier: "com.spotify.client",
            bundleIdentifier: "com.apple.MediaPlayer",
            volume: nil
        )

        guard case let .active(snapshot) = payload.normalizedState else {
            return XCTFail("Expected active normalized state")
        }

        XCTAssertEqual(snapshot.source.displayName, "Spotify")
        XCTAssertEqual(snapshot.source.bundleIdentifier, "com.spotify.client")
    }

    func testPayloadWithoutTrackMetadataNormalizesToIdle() {
        let payload = NowPlayingSessionPayload(
            title: nil,
            artist: nil,
            album: nil,
            duration: nil,
            elapsedTime: nil,
            artworkData: nil,
            timestamp: nil,
            playbackRate: nil,
            isPlaying: nil,
            parentApplicationBundleIdentifier: nil,
            bundleIdentifier: nil,
            volume: nil
        )

        XCTAssertEqual(payload.normalizedState, .idle)
    }

    func testEstimatedCurrentTimeAdvancesWhilePlaying() {
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 30,
            duration: 240,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            snapshot.estimatedCurrentTime(at: Date(timeIntervalSince1970: 103)),
            33,
            accuracy: 0.01
        )
    }

    func testEstimatedCurrentTimeClampsToDuration() {
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 211,
            duration: 213,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            snapshot.estimatedCurrentTime(at: Date(timeIntervalSince1970: 110)),
            213,
            accuracy: 0.01
        )
    }

    func testMediaPlaybackSnapshotCanReplaceCurrentTimeForDirectPlayerReads() {
        let captureDate = Date(timeIntervalSince1970: 120)
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Track",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 30,
            duration: 240,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        let directSnapshot = snapshot.replacingCurrentTime(42, at: captureDate)

        XCTAssertEqual(directSnapshot.currentTime, 42)
        XCTAssertEqual(directSnapshot.lastUpdated, captureDate)
        XCTAssertEqual(directSnapshot.estimatedCurrentTime(at: captureDate), 42, accuracy: 0.01)
    }

    func testAppleScriptPlaybackTimeProviderReadsSpotifyPlayerPosition() {
        var receivedScripts: [String] = []
        let provider = AppleScriptPlaybackTimeProvider(
            scriptRunner: { script in
                receivedScripts.append(script)
                return 42.5
            },
            isApplicationRunning: { bundleIdentifier in
                bundleIdentifier == "com.spotify.client"
            }
        )

        let playbackTime = provider.currentPlaybackTime(
            for: .fromBundleIdentifier("com.spotify.client")
        )

        XCTAssertEqual(playbackTime, 42.5)
        XCTAssertEqual(receivedScripts.count, 1)
        XCTAssertTrue(receivedScripts[0].contains("tell application \"Spotify\""))
        XCTAssertFalse(receivedScripts[0].contains("application id"))
        XCTAssertTrue(receivedScripts[0].contains("player position"))
    }

    func testAppleScriptPlaybackTimeProviderDoesNotRunScriptWhenPlayerIsNotRunning() {
        var didRunScript = false
        let provider = AppleScriptPlaybackTimeProvider(
            scriptRunner: { _ in
                didRunScript = true
                return 12
            },
            isApplicationRunning: { _ in false }
        )

        XCTAssertNil(
            provider.currentPlaybackTime(
                for: .fromBundleIdentifier("com.spotify.client")
            )
        )
        XCTAssertFalse(didRunScript)
    }

    func testAppleScriptPlaybackTimeProviderIgnoresUnsupportedPlayers() {
        var didRunScript = false
        let provider = AppleScriptPlaybackTimeProvider { _ in
            didRunScript = true
            return 12
        }

        XCTAssertNil(
            provider.currentPlaybackTime(
                for: .fromBundleIdentifier("com.tencent.qqmusic")
            )
        )
        XCTAssertFalse(didRunScript)
    }
}
