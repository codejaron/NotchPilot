import XCTest
@testable import NotchPilotKit

final class MediaPlaybackStateSelectorTests: XCTestCase {
    func testSpotifyPlayingStateIsUsedWhenMediaRemoteTurnsIdle() {
        let date = Date(timeIntervalSince1970: 100)
        var selector = MediaPlaybackStateSelector()

        let selected = selector.acceptSpotify(
            .active(Self.snapshot(
                bundleIdentifier: "com.spotify.client",
                title: "Song",
                artist: "Artist",
                currentTime: 10,
                isPlaying: true,
                lastUpdated: date
            )),
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

        let reconciled = selector.acceptSystem(.idle, at: date.addingTimeInterval(2))

        guard case let .active(snapshot) = reconciled else {
            return XCTFail("Expected Spotify to remain selected")
        }
        XCTAssertEqual(snapshot.source.bundleIdentifier, "com.spotify.client")
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.currentTime, 12, accuracy: 0.01)
    }

    func testSpotifyPausedStateDoesNotOverrideAnotherPlayingSource() {
        let date = Date(timeIntervalSince1970: 200)
        var selector = MediaPlaybackStateSelector()
        let appleMusic = Self.snapshot(
            bundleIdentifier: "com.apple.Music",
            title: "Apple Song",
            artist: "Apple Artist",
            currentTime: 40,
            isPlaying: true,
            lastUpdated: date
        )

        _ = selector.acceptSystem(.active(appleMusic), at: date)
        let selected = selector.acceptSpotify(
            .active(Self.snapshot(
                bundleIdentifier: "com.spotify.client",
                title: "Spotify Song",
                artist: "Spotify Artist",
                currentTime: 20,
                playbackRate: 0,
                isPlaying: false,
                lastUpdated: date
            )),
            at: date
        )

        XCTAssertEqual(selected, .active(appleMusic))
    }

    func testSpotifyStoppedStateDoesNotClearAnotherPlayingSource() {
        let date = Date(timeIntervalSince1970: 300)
        var selector = MediaPlaybackStateSelector()
        let appleMusic = Self.snapshot(
            bundleIdentifier: "com.apple.Music",
            title: "Apple Song",
            artist: "Apple Artist",
            currentTime: 40,
            isPlaying: true,
            lastUpdated: date
        )

        _ = selector.acceptSystem(.active(appleMusic), at: date)
        let selected = selector.acceptSpotify(.idle, at: date)

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
