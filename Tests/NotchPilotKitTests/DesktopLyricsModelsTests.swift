import XCTest
@testable import NotchPilotKit

final class DesktopLyricsModelsTests: XCTestCase {
    func testLyricsTrackKeyNormalizesWhitespaceAndPunctuation() {
        let lhs = LyricsTrackKey(
            title: "  Song - Title ",
            artist: "Artist, Name",
            album: "Album",
            duration: 213.4
        )
        let rhs = LyricsTrackKey(
            title: "song title",
            artist: "artist name",
            album: "album",
            duration: 213.49
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.storageIdentifier, rhs.storageIdentifier)
    }

    func testTimedLyricsPairResolvesCurrentAndNextLine() {
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0, text: "intro"),
                TimedLyricLine(timestamp: 12, text: "current"),
                TimedLyricLine(timestamp: 18, text: "next"),
            ]
        )

        let pair = lyrics.linePair(at: 13)

        XCTAssertEqual(pair?.current.text, "current")
        XCTAssertEqual(pair?.next?.text, "next")
    }

    func testDesktopLyricsPresentationResolverHidesWhenPlaybackPaused() {
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [TimedLyricLine(timestamp: 0, text: "line")]
        )

        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 15,
            duration: 200,
            playbackRate: 1,
            isPlaying: false,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        let presentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: .active(snapshot),
            lyrics: lyrics,
            at: Date(timeIntervalSince1970: 105)
        )

        XCTAssertFalse(presentation.isVisible)
        XCTAssertNil(presentation.currentLine)
        XCTAssertNil(presentation.nextLine)
    }

    func testDesktopLyricsPresentationResolverShowsCurrentAndNextLine() {
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0, text: "line 1"),
                TimedLyricLine(timestamp: 15, text: "line 2"),
                TimedLyricLine(timestamp: 30, text: "line 3"),
            ]
        )

        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 16,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        let presentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: .active(snapshot),
            lyrics: lyrics,
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.currentLine, "line 2")
        XCTAssertEqual(presentation.nextLine, "line 3")
    }

    func testDesktopLyricsPresentationResolverPrefersTranslationOverNextLine() {
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0, text: "line 1"),
                TimedLyricLine(timestamp: 15, text: "line 2", translation: "第二行"),
                TimedLyricLine(timestamp: 30, text: "line 3"),
            ]
        )

        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 16,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        let presentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: .active(snapshot),
            lyrics: lyrics,
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.currentLine, "line 2")
        XCTAssertEqual(presentation.nextLine, "第二行")
    }
}
