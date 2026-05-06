import LyricsKit
import XCTest
@testable import NotchPilotKit

final class LyricsProviderTests: XCTestCase {
    func testTimedLyricsInitializesFromLyricsKitLyrics() throws {
        let lyrics = Lyrics(
            lines: [
                LyricsLine(content: "line 1", position: 1),
                LyricsLine(content: "line 2", position: 4),
            ],
            idTags: [
                .title: "Song",
                .artist: "Artist",
                .album: "Album",
            ]
        )
        lyrics.length = 200

        let timedLyrics = try XCTUnwrap(TimedLyrics(lyricsKitLyrics: lyrics, service: "QQMusic"))

        XCTAssertEqual(timedLyrics.title, "Song")
        XCTAssertEqual(timedLyrics.artist, "Artist")
        XCTAssertEqual(timedLyrics.album, "Album")
        XCTAssertEqual(try XCTUnwrap(timedLyrics.duration), 200, accuracy: 0.01)
        XCTAssertEqual(timedLyrics.service, "QQMusic")
        XCTAssertEqual(timedLyrics.lines.map(\.text), ["line 1", "line 2"])
    }

    func testTimedLyricsInitializesTranslationFromLyricsKitAttachments() throws {
        let lyrics = Lyrics(
            lines: [
                LyricsLine(
                    content: "hello",
                    position: 1,
                    attachments: LyricsLine.Attachments(
                        attachments: [
                            .translation(): LyricsLine.Attachments.PlainText("你好"),
                        ]
                    )
                ),
            ],
            idTags: [
                .title: "Song",
                .artist: "Artist",
            ]
        )

        let timedLyrics = try XCTUnwrap(TimedLyrics(lyricsKitLyrics: lyrics, service: "QQMusic"))

        XCTAssertEqual(timedLyrics.lines.first?.translation, "你好")
    }

    @MainActor
    func testCachedLyricsProviderReturnsCachedLyricsWithoutInvokingRemote() async {
        let cachedLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [TimedLyricLine(timestamp: 0, text: "cached")]
        )
        let cache = TestLyricsCache(loadedLyrics: cachedLyrics)
        let remote = TestLyricsProvider(result: nil)
        let provider = CachedLyricsProvider(cache: cache, remoteProvider: remote)

        let result = await provider.lyrics(for: Self.snapshot())

        XCTAssertEqual(result, cachedLyrics)
        let requestCount = remote.requestedSnapshots.count
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testCachedLyricsProviderStoresRemoteLyricsOnCacheMiss() async {
        let remoteLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "remote")]
        )
        let cache = TestLyricsCache(loadedLyrics: nil)
        let remote = TestLyricsProvider(result: remoteLyrics)
        let provider = CachedLyricsProvider(cache: cache, remoteProvider: remote)

        let result = await provider.lyrics(for: Self.snapshot())

        XCTAssertEqual(result, remoteLyrics)
        let requestCount = remote.requestedSnapshots.count
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(cache.savedLyrics, remoteLyrics)
    }

    @MainActor
    func testLyricsKitProviderSearchAggregatesCandidatesWithoutLoadingLyrics() async {
        let candidateA = LyricsSearchCandidate(
            id: "qq|artist|song",
            title: "Song",
            artist: "Artist",
            service: "QQMusic",
            loadLyrics: {
                XCTFail("Search should not eagerly load lyrics")
                return Self.makeLyrics(service: "QQMusic")
            }
        )
        let candidateB = LyricsSearchCandidate(
            id: "netease|artist|song",
            title: "Song",
            artist: "Artist",
            service: "NetEase",
            loadLyrics: {
                XCTFail("Search should not eagerly load lyrics")
                return Self.makeLyrics(service: "NetEase")
            }
        )

        let serviceA = TestLyricsSearchService(results: [candidateA])
        let serviceB = TestLyricsSearchService(results: [candidateB])
        let provider = LyricsKitProvider(searchServices: [serviceA, serviceB])

        let results = await provider.searchLyrics(
            title: "Song",
            artist: "Artist",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results, [candidateA, candidateB])
        XCTAssertEqual(serviceA.requests.count, 1)
        XCTAssertEqual(serviceB.requests.count, 1)
    }

    @MainActor
    func testLyricsKitProviderSearchDeduplicatesWithinSameService() async {
        let duplicateA = LyricsSearchCandidate(
            id: "qq|artist|song|1",
            title: "Song",
            artist: "Artist",
            service: "QQMusic",
            loadLyrics: { Self.makeLyrics(service: "QQMusic") }
        )
        let duplicateB = LyricsSearchCandidate(
            id: "qq|artist|song|2",
            title: "SONG",
            artist: "ARTIST",
            service: "QQMusic",
            loadLyrics: { Self.makeLyrics(service: "QQMusic") }
        )
        let provider = LyricsKitProvider(
            searchServices: [
                TestLyricsSearchService(results: [duplicateA, duplicateB]),
            ]
        )

        let results = await provider.searchLyrics(
            title: "Song",
            artist: "Artist",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results, [duplicateA])
    }

    func testLyricsCachePersistsLyricsUsingTrackKeyFileName() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let cache = LyricsCache(directoryURL: directoryURL, fileManager: .default)
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "line")]
        )
        let key = LyricsTrackKey(title: "Song", artist: "Artist", album: "Album", duration: 200)

        try cache.saveLyrics(lyrics, for: key)

        XCTAssertEqual(cache.loadLyrics(for: key), lyrics)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directoryURL.appendingPathComponent(key.cacheFileName).path
            )
        )
        XCTAssertEqual(key.cacheFileName, "artist - song.json")
    }

    func testLyricsTrackKeyCacheFileNameIsStableAcrossCasingAndPadding() {
        let canonical = LyricsTrackKey(title: "Yellow", artist: "Coldplay", album: "", duration: 200)
        let variantCase = LyricsTrackKey(title: "YELLOW", artist: "coldplay", album: "", duration: 200)
        let variantPadding = LyricsTrackKey(title: " Yellow ", artist: "  Coldplay ", album: "", duration: 200)
        let variantPunctuation = LyricsTrackKey(title: "Yellow!", artist: "Coldplay.", album: "", duration: 200)

        XCTAssertEqual(canonical.cacheFileName, variantCase.cacheFileName)
        XCTAssertEqual(canonical.cacheFileName, variantPadding.cacheFileName)
        XCTAssertEqual(canonical.cacheFileName, variantPunctuation.cacheFileName)
    }

    @MainActor
    func testCachedLyricsProviderDoesNotInvokeRemoteOnCacheHit() async {
        let cachedLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [TimedLyricLine(timestamp: 0, text: "cached")]
        )
        let cache = TestLyricsCache(loadedLyrics: cachedLyrics)
        let remote = TestLyricsProvider(result: nil)
        let provider = CachedLyricsProvider(cache: cache, remoteProvider: remote)

        _ = await provider.lyrics(for: Self.snapshot())
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(remote.requestedSnapshots.count, 0)
        XCTAssertNil(cache.savedLyrics)
    }

    @MainActor
    func testCachedLyricsProviderDoesNotOverwriteCacheAfterMissReturn() async {
        let lyricsWithoutInlineTags = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "remote", inlineTags: nil)]
        )
        let cache = TestLyricsCache(loadedLyrics: nil)
        let remote = TestLyricsProvider(result: lyricsWithoutInlineTags)
        let provider = CachedLyricsProvider(cache: cache, remoteProvider: remote)

        _ = await provider.lyrics(for: Self.snapshot())
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(remote.requestedSnapshots.count, 1)
        XCTAssertEqual(cache.savedLyrics, lyricsWithoutInlineTags)
        XCTAssertEqual(cache.saveCallCount, 1, "Cache must not be touched again after the initial save")
    }

    func testTimedLyricsFallsBackToProvidedTitleAndArtistWhenIdTagsAreMissing() throws {
        let lyrics = Lyrics(
            lines: [LyricsLine(content: "line", position: 1)],
            idTags: [:]
        )

        let timedLyrics = try XCTUnwrap(
            TimedLyrics(
                lyricsKitLyrics: lyrics,
                service: "NetEase",
                fallbackTitle: "Fallback Song",
                fallbackArtist: "Fallback Artist"
            )
        )

        XCTAssertEqual(timedLyrics.title, "Fallback Song")
        XCTAssertEqual(timedLyrics.artist, "Fallback Artist")
    }

    func testTimedLyricsPrefersIdTagsOverFallbackWhenPresent() throws {
        let lyrics = Lyrics(
            lines: [LyricsLine(content: "line", position: 1)],
            idTags: [
                .title: "Real Title",
                .artist: "Real Artist",
            ]
        )

        let timedLyrics = try XCTUnwrap(
            TimedLyrics(
                lyricsKitLyrics: lyrics,
                service: "QQMusic",
                fallbackTitle: "Fallback",
                fallbackArtist: "Fallback"
            )
        )

        XCTAssertEqual(timedLyrics.title, "Real Title")
        XCTAssertEqual(timedLyrics.artist, "Real Artist")
    }

    func testLyricsCacheRemovesPersistedLyrics() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let cache = LyricsCache(directoryURL: directoryURL, fileManager: .default)
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "line")]
        )
        let key = LyricsTrackKey(title: "Song", artist: "Artist", album: "Album", duration: 200)

        try cache.saveLyrics(lyrics, for: key)
        try cache.removeLyrics(for: key)

        XCTAssertNil(cache.loadLyrics(for: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL(for: key).path))
    }

    func testIgnoredLyricsTrackStorePersistsInsertedKeys() {
        let suiteName = "IgnoredLyricsTrackStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = IgnoredLyricsTrackStore(defaults: defaults)
        let key = LyricsTrackKey(title: "Song", artist: "Artist", album: "Album", duration: 200)

        XCTAssertFalse(store.contains(key))

        store.insert(key)

        let reloadedStore = IgnoredLyricsTrackStore(defaults: defaults)
        XCTAssertTrue(reloadedStore.contains(key))
    }

    func testIgnoredLyricsTrackStoreRemovesPersistedKeys() {
        let suiteName = "IgnoredLyricsTrackStoreRemoveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let key = LyricsTrackKey(title: "Song", artist: "Artist", album: "Album", duration: 200)
        let store = IgnoredLyricsTrackStore(defaults: defaults)

        store.insert(key)
        store.remove(key)

        let reloadedStore = IgnoredLyricsTrackStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.contains(key))
    }

    func testPlaybackFilterRejectsChromeBundleIdentifier() {
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.google.Chrome"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 12,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        XCTAssertFalse(DesktopLyricsPlaybackFilter.isEligible(snapshot))
    }

    func testPlaybackFilterAllowsSpotifyBundleIdentifier() {
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 12,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(DesktopLyricsPlaybackFilter.isEligible(snapshot))
    }

    func testPlaybackFilterAllowsQQMusicBundleIdentifier() {
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.tencent.qqmusic"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 12,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(DesktopLyricsPlaybackFilter.isEligible(snapshot))
    }

    private static func snapshot() -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 12,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
    }

    private static func makeLyrics(service: String) -> TimedLyrics {
        TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: service,
            lines: [TimedLyricLine(timestamp: 0, text: "line")]
        )
    }
}

private final class TestLyricsCache: LyricsCaching {
    var loadedLyrics: TimedLyrics?
    private(set) var savedLyrics: TimedLyrics?
    private(set) var saveCallCount: Int = 0

    init(loadedLyrics: TimedLyrics?) {
        self.loadedLyrics = loadedLyrics
    }

    func loadLyrics(for key: LyricsTrackKey) -> TimedLyrics? {
        loadedLyrics
    }

    func saveLyrics(_ lyrics: TimedLyrics, for key: LyricsTrackKey) throws {
        savedLyrics = lyrics
        saveCallCount += 1
    }

    func fileURL(for key: LyricsTrackKey) -> URL {
        URL(fileURLWithPath: "/tmp/\(key.cacheFileName)")
    }

    func removeLyrics(for key: LyricsTrackKey) throws {}
}

@MainActor
private final class TestLyricsProvider: LyricsProviding {
    let result: TimedLyrics?
    private(set) var requestedSnapshots: [MediaPlaybackSnapshot] = []

    init(result: TimedLyrics?) {
        self.result = result
    }

    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        requestedSnapshots.append(snapshot)
        return result
    }
}

@MainActor
private final class TestLyricsSearchService: LyricsSearchServicing {
    private(set) var requests: [LyricsSearchRequest] = []
    let results: [LyricsSearchCandidate]

    init(results: [LyricsSearchCandidate]) {
        self.results = results
    }

    func searchCandidates(
        for request: LyricsSearchRequest,
        limit: Int
    ) async -> [LyricsSearchCandidate] {
        requests.append(request)
        return Array(results.prefix(limit))
    }
}
