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

    func testPlaybackTimeResolverUsesProjectedAnchorWhenSameTrackReportsTransientZero() {
        var resolver = MediaPlaybackTimeResolver()
        let start = Date(timeIntervalSince1970: 100)
        let first = Self.activeSnapshot(
            title: "Track",
            artist: "Artist",
            currentTime: 42,
            duration: 200,
            isPlaying: true,
            lastUpdated: start
        )
        let zero = Self.activeSnapshot(
            title: "Track",
            artist: "Artist",
            currentTime: 0,
            duration: 200,
            isPlaying: true,
            lastUpdated: start.addingTimeInterval(1)
        )

        _ = resolver.resolve(.active(first), receivedAt: start)
        let resolved = resolver.resolve(.active(zero), receivedAt: start.addingTimeInterval(1))

        guard case let .active(snapshot) = resolved else {
            return XCTFail("Expected active snapshot")
        }
        XCTAssertEqual(snapshot.currentTime, 43, accuracy: 0.01)
        XCTAssertEqual(snapshot.lastUpdated, start.addingTimeInterval(1))
    }

    func testPlaybackTimeResolverUsesProjectionDateAsSnapshotAnchor() {
        var resolver = MediaPlaybackTimeResolver()
        let start = Date(timeIntervalSince1970: 100)
        let first = Self.activeSnapshot(
            currentTime: 42,
            duration: 200,
            isPlaying: true,
            lastUpdated: start
        )
        let zero = Self.activeSnapshot(
            currentTime: 0,
            duration: 200,
            isPlaying: true,
            lastUpdated: start.addingTimeInterval(1)
        )
        let receivedAt = start.addingTimeInterval(2)

        _ = resolver.resolve(.active(first), receivedAt: start)
        let resolved = resolver.resolve(.active(zero), receivedAt: receivedAt)

        guard case let .active(snapshot) = resolved else {
            return XCTFail("Expected active snapshot")
        }
        XCTAssertEqual(snapshot.currentTime, 44, accuracy: 0.01)
        XCTAssertEqual(snapshot.lastUpdated, receivedAt)
        XCTAssertEqual(snapshot.estimatedCurrentTime(at: receivedAt), 44, accuracy: 0.01)
    }

    func testPlaybackTimeResolverDoesNotReuseAnchorAfterValidityWindow() {
        var resolver = MediaPlaybackTimeResolver(anchorValidity: 12)
        let start = Date(timeIntervalSince1970: 100)
        let first = Self.activeSnapshot(
            currentTime: 42,
            duration: 200,
            isPlaying: true,
            lastUpdated: start
        )
        let staleZero = Self.activeSnapshot(
            currentTime: 0,
            duration: 200,
            isPlaying: true,
            lastUpdated: start.addingTimeInterval(13)
        )

        _ = resolver.resolve(.active(first), receivedAt: start)
        let resolved = resolver.resolve(.active(staleZero), receivedAt: start.addingTimeInterval(13))

        XCTAssertEqual(resolved, .active(staleZero))
    }

    func testPlaybackTimeResolverDoesNotReuseAnchorForDifferentTrack() {
        var resolver = MediaPlaybackTimeResolver()
        let start = Date(timeIntervalSince1970: 100)
        let first = Self.activeSnapshot(
            title: "Track A",
            currentTime: 42,
            duration: 200,
            isPlaying: true,
            lastUpdated: start
        )
        let other = Self.activeSnapshot(
            title: "Track B",
            currentTime: 0,
            duration: 200,
            isPlaying: true,
            lastUpdated: start.addingTimeInterval(1)
        )

        _ = resolver.resolve(.active(first), receivedAt: start)
        let resolved = resolver.resolve(.active(other), receivedAt: start.addingTimeInterval(1))

        XCTAssertEqual(resolved, .active(other))
    }

    @MainActor
    func testAppleScriptPlaybackTimeProviderReadsSpotifyPlayerPosition() async {
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

        let playbackTime = await provider.currentPlaybackTime(
            for: .fromBundleIdentifier("com.spotify.client")
        )

        XCTAssertEqual(playbackTime, 42.5)
        XCTAssertEqual(receivedScripts.count, 1)
        XCTAssertTrue(receivedScripts[0].contains("tell application \"Spotify\""))
        XCTAssertFalse(receivedScripts[0].contains("application id"))
        XCTAssertTrue(receivedScripts[0].contains("player position"))
    }

    @MainActor
    func testAppleScriptPlaybackTimeProviderCachesRecentSuccessfulRead() async {
        var receivedScripts: [String] = []
        let provider = AppleScriptPlaybackTimeProvider(
            scriptRunner: { script in
                receivedScripts.append(script)
                return 42.5
            },
            isApplicationRunning: { _ in true },
            cacheDuration: 1,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let source = MediaPlaybackSource.fromBundleIdentifier("com.spotify.client")

        let first = await provider.currentPlaybackTime(for: source)
        let second = await provider.currentPlaybackTime(for: source)

        XCTAssertEqual(first, 42.5)
        XCTAssertEqual(second, 42.5)
        XCTAssertEqual(receivedScripts.count, 1)
    }

    @MainActor
    func testAppleScriptPlaybackTimeProviderDoesNotRunScriptWhenPlayerIsNotRunning() async {
        var didRunScript = false
        let provider = AppleScriptPlaybackTimeProvider(
            scriptRunner: { _ in
                didRunScript = true
                return 12
            },
            isApplicationRunning: { _ in false }
        )

        let playbackTime = await provider.currentPlaybackTime(
            for: .fromBundleIdentifier("com.spotify.client")
        )
        XCTAssertNil(playbackTime)
        XCTAssertFalse(didRunScript)
    }

    @MainActor
    func testAppleScriptPlaybackTimeProviderIgnoresUnsupportedPlayers() async {
        var didRunScript = false
        let provider = AppleScriptPlaybackTimeProvider { _ in
            didRunScript = true
            return 12
        }

        let playbackTime = await provider.currentPlaybackTime(
            for: .fromBundleIdentifier("com.tencent.qqmusic")
        )
        XCTAssertNil(playbackTime)
        XCTAssertFalse(didRunScript)
    }

    private static func activeSnapshot(
        source: MediaPlaybackSource = .fromBundleIdentifier("com.spotify.client"),
        title: String = "Track",
        artist: String = "Artist",
        album: String = "Album",
        currentTime: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool,
        lastUpdated: Date
    ) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: source,
            title: title,
            artist: artist,
            album: album,
            artworkData: nil,
            currentTime: currentTime,
            duration: duration,
            playbackRate: isPlaying ? 1 : 0,
            isPlaying: isPlaying,
            lastUpdated: lastUpdated
        )
    }
}
