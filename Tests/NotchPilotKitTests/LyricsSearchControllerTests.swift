import XCTest
@testable import NotchPilotKit

final class LyricsSearchControllerTests: XCTestCase {
    @MainActor
    func testSearchControllerPrefillsBindingTrackMetadata() {
        let controller = LyricsSearchController(
            bindingSnapshot: Self.snapshot(title: "As If It's Your Last", artist: "BLACKPINK"),
            searchProvider: TestLyricsSearchProvider(results: []),
            applyHandler: { _ in }
        )

        XCTAssertEqual(controller.searchTitle, "As If It's Your Last")
        XCTAssertEqual(controller.searchArtist, "BLACKPINK")
        XCTAssertEqual(controller.bindingDisplayTitle, "BLACKPINK - As If It's Your Last")
    }

    @MainActor
    func testSearchControllerSearchesCandidatesLoadsSelectionAndAppliesLyrics() async {
        let searchedLyrics = TimedLyrics(
            title: "AS IF IT'S YOUR LAST",
            artist: "BLACKPINK",
            album: "",
            duration: 210,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "line 1")]
        )
        let candidate = LyricsSearchCandidate(
            id: "qq|blackpink|as if it's your last",
            title: searchedLyrics.title,
            artist: searchedLyrics.artist,
            service: searchedLyrics.service,
            loadLyrics: { searchedLyrics }
        )
        let provider = TestLyricsSearchProvider(results: [candidate])
        var appliedLyrics: TimedLyrics?
        var previewedLyrics: TimedLyrics?
        let controller = LyricsSearchController(
            bindingSnapshot: Self.snapshot(title: "As If It's Your Last", artist: "BLACKPINK"),
            searchProvider: provider,
            applyHandler: { appliedLyrics = $0 },
            previewHandler: { previewedLyrics = $0 }
        )

        await controller.search()
        await controller.loadSelectedLyrics()
        controller.applySelectedLyrics()

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(provider.requests.first?.title, "As If It's Your Last")
        XCTAssertEqual(provider.requests.first?.artist, "BLACKPINK")
        XCTAssertEqual(controller.results, [candidate])
        XCTAssertEqual(controller.selectedLyrics, searchedLyrics)
        XCTAssertEqual(previewedLyrics, searchedLyrics)
        XCTAssertEqual(appliedLyrics, searchedLyrics)
    }

    @MainActor
    func testSearchControllerRetainsCandidatesWhenSelectedLyricsFailToLoad() async {
        let candidate = LyricsSearchCandidate(
            id: "qq|blackpink|broken",
            title: "Broken",
            artist: "BLACKPINK",
            service: "QQMusic",
            loadLyrics: { throw TestLyricsSearchError.failedToLoad }
        )
        let controller = LyricsSearchController(
            bindingSnapshot: Self.snapshot(title: "As If It's Your Last", artist: "BLACKPINK"),
            searchProvider: TestLyricsSearchProvider(results: [candidate]),
            applyHandler: { _ in }
        )

        await controller.search()
        await controller.loadSelectedLyrics()

        XCTAssertEqual(controller.results, [candidate])
        XCTAssertNil(controller.selectedLyrics)
        XCTAssertEqual(controller.errorMessage, "无法加载所选歌词。")
    }

    private static func snapshot(title: String, artist: String) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: title,
            artist: artist,
            album: "",
            artworkData: nil,
            currentTime: 12,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
    }
}

@MainActor
private final class TestLyricsSearchProvider: LyricsSearching {
    struct Request: Equatable {
        let title: String
        let artist: String
        let duration: TimeInterval?
        let limit: Int
    }

    private(set) var requests: [Request] = []
    let results: [LyricsSearchCandidate]

    init(results: [LyricsSearchCandidate]) {
        self.results = results
    }

    func searchLyrics(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int
    ) async -> [LyricsSearchCandidate] {
        requests.append(.init(title: title, artist: artist, duration: duration, limit: limit))
        return results
    }
}

private enum TestLyricsSearchError: Error {
    case failedToLoad
}
