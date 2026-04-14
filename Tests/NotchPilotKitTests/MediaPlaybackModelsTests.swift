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
}
