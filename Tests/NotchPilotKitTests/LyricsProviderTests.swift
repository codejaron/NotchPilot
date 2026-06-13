import LyricsKit
@preconcurrency import LyricsService
import XCTest
@testable import NotchPilotKit

final class LyricsProviderTests: XCTestCase {
    func testDefaultLyricsKitServicesExcludeKnownHTTPProviders() {
        let serviceNames = LyricsKitServiceConfiguration.services(allowInsecureHTTP: false)
            .map(\.displayName)

        XCTAssertTrue(serviceNames.contains("QQMusic"))
        XCTAssertTrue(serviceNames.contains("Musixmatch"))
        XCTAssertTrue(serviceNames.contains("LRCLIB"))
        XCTAssertFalse(serviceNames.contains("Kugou"))
        XCTAssertFalse(serviceNames.contains("Netease"))
    }

    func testLyricsKitServicesCanIncludeKnownHTTPProvidersWhenAllowed() {
        let serviceNames = LyricsKitServiceConfiguration.services(allowInsecureHTTP: true)
            .map(\.displayName)

        XCTAssertTrue(serviceNames.contains("Kugou"))
        XCTAssertTrue(serviceNames.contains("Netease"))
    }

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

    func testTimedLyricsKeepsTimedMetadataAndCreditLines() throws {
        let lyrics = Lyrics(
            lines: [
                LyricsLine(content: "Artist - Song", position: 0),
                LyricsLine(content: "作词：Someone", position: 0),
                LyricsLine(content: "词：Someone", position: 1),
                LyricsLine(content: "曲：Someone", position: 2),
                LyricsLine(content: "Lyrics: bad.example.com", position: 3),
                LyricsLine(content: "real line", position: 4),
                LyricsLine(content: "www.bad-lyrics.example", position: 5),
                LyricsLine(content: ".", position: 6),
            ],
            idTags: [
                .title: "Song",
                .artist: "Artist",
            ]
        )

        let timedLyrics = try XCTUnwrap(TimedLyrics(lyricsKitLyrics: lyrics, service: "QQMusic"))

        XCTAssertEqual(
            timedLyrics.lines.map(\.text),
            [
                "Artist - Song",
                "作词：Someone",
                "词：Someone",
                "曲：Someone",
                "Lyrics: bad.example.com",
                "real line",
                "www.bad-lyrics.example",
                ".",
            ]
        )
    }

    func testTimedLyricsRejectsLyricsWithOnlyEmptyLines() {
        let lyrics = Lyrics(
            lines: [
                LyricsLine(content: "", position: 0),
                LyricsLine(content: "   ", position: 1),
            ],
            idTags: [
                .title: "Song",
                .artist: "Artist",
            ]
        )

        XCTAssertNil(TimedLyrics(lyricsKitLyrics: lyrics, service: "QQMusic"))
    }

    func testTimedLyricsTruncatesOverlongLines() throws {
        let lyrics = Lyrics(
            lines: [
                LyricsLine(
                    content: String(repeating: "a", count: TimedLyrics.maxLineCharacterCount + 25),
                    position: 1
                ),
            ],
            idTags: [
                .title: "Song",
                .artist: "Artist",
            ]
        )

        let timedLyrics = try XCTUnwrap(TimedLyrics(lyricsKitLyrics: lyrics, service: "LRCLIB"))
        XCTAssertEqual(timedLyrics.lines.first?.text.count, TimedLyrics.maxLineCharacterCount)
    }

    func testTimedLyricsLimitsExternalLineCount() throws {
        let lines = (0..<(TimedLyrics.maxLineCount + 25)).map { index in
            LyricsLine(content: "line \(index)", position: TimeInterval(index))
        }
        let lyrics = Lyrics(
            lines: lines,
            idTags: [
                .title: "Song",
                .artist: "Artist",
            ]
        )

        let timedLyrics = try XCTUnwrap(TimedLyrics(lyricsKitLyrics: lyrics, service: "LRCLIB"))
        XCTAssertEqual(timedLyrics.lines.count, TimedLyrics.maxLineCount)
    }

    func testTimedLyricsRejectsOversizedExternalPayload() {
        let lines = (0..<300).map { index in
            LyricsLine(
                content: String(repeating: "x", count: 1_000),
                position: TimeInterval(index)
            )
        }
        let lyrics = Lyrics(
            lines: lines,
            idTags: [
                .title: "Song",
                .artist: "Artist",
            ]
        )

        XCTAssertNil(TimedLyrics(lyricsKitLyrics: lyrics, service: "LRCLIB"))
    }

    func testTimedLyricsInitializesWhenArtistMetadataIsMissing() throws {
        let lyrics = Lyrics(
            lines: [
                LyricsLine(content: "line", position: 1),
            ],
            idTags: [
                .title: "Song",
            ]
        )

        let timedLyrics = try XCTUnwrap(
            TimedLyrics(
                lyricsKitLyrics: lyrics,
                service: "LRCLIB",
                fallbackTitle: "Song",
                fallbackArtist: ""
            )
        )

        XCTAssertEqual(timedLyrics.title, "Song")
        XCTAssertEqual(timedLyrics.artist, "")
        XCTAssertEqual(timedLyrics.lines.map(\.text), ["line"])
    }

    func testTimedLyricsAppliesLyricsKitOffsetWhenResolvingPresentation() throws {
        let lyrics = Lyrics(
            lines: [
                LyricsLine(content: "line 1", position: 10),
                LyricsLine(content: "line 2", position: 15),
            ],
            idTags: [
                .title: "Song",
                .artist: "Artist",
            ]
        )
        lyrics.offset = 2_000

        let timedLyrics = try XCTUnwrap(TimedLyrics(lyricsKitLyrics: lyrics, service: "QQMusic"))
        let captureDate = Date(timeIntervalSince1970: 100)
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Song",
            artist: "Artist",
            album: "",
            artworkData: nil,
            currentTime: 13,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: captureDate
        )
        let presentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: .active(snapshot),
            lyrics: timedLyrics,
            at: captureDate
        )

        XCTAssertEqual(presentation.currentLine, "line 2")
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
    func testLyricsKitProviderSearchAggregatesCandidatesAcrossServices() async {
        let candidateA = LyricsSearchCandidate(
            id: "qq|artist|song",
            title: "Song",
            artist: "Artist",
            service: "QQMusic",
            loadLyrics: {
                Self.makeLyrics(service: "QQMusic")
            }
        )
        let candidateB = LyricsSearchCandidate(
            id: "netease|artist|song",
            title: "Song",
            artist: "Artist",
            service: "NetEase",
            loadLyrics: {
                Self.makeLyrics(service: "NetEase")
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

        XCTAssertEqual(Set(results.map(\.id)), Set([candidateA.id, candidateB.id]))
        XCTAssertEqual(serviceA.requests.count, 1)
        XCTAssertEqual(serviceB.requests.count, 1)
    }

    @MainActor
    func testLyricsKitProviderAutomaticUpdatesFallBackToManualSearchPathWhenArtistIsMissing() async {
        let remoteLyrics = TimedLyrics(
            title: "Song",
            artist: "",
            album: "",
            duration: 200,
            service: "Kugou",
            lines: [TimedLyricLine(timestamp: 0, text: "line")]
        )
        let candidate = LyricsSearchCandidate(
            id: "kugou||song",
            title: "Song",
            artist: "",
            service: "Kugou",
            quality: 0.8,
            duration: 200,
            loadLyrics: { remoteLyrics }
        )
        let service = TestLyricsSearchService(results: [candidate])
        let rawProvider = EmptyLyricsServiceProvider()
        let provider = LyricsKitProvider(
            provider: rawProvider,
            searchServices: [service]
        )
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot(artist: "")) {
            updates.append(lyrics)
        }

        XCTAssertEqual(updates, [remoteLyrics])
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(rawProvider.requests.count, 1)
    }

    @MainActor
    func testLyricsKitProviderAutomaticUpdatesUseProviderStreamWhenArtistIsMissing() async throws {
        let lyrics = Lyrics(
            lines: [LyricsLine(content: "line", position: 0)],
            idTags: [.title: "Song"]
        )
        let rawProvider = StaticLyricsServiceProvider(lyrics: [lyrics])
        let service = TestLyricsSearchService(results: [])
        let provider = LyricsKitProvider(
            provider: rawProvider,
            searchServices: [service]
        )
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot(artist: "")) {
            updates.append(lyrics)
        }

        let update = try XCTUnwrap(updates.first)
        XCTAssertEqual(update.title, "Song")
        XCTAssertEqual(update.artist, "")
        XCTAssertEqual(update.lines.map(\.text), ["line"])
        XCTAssertEqual(service.requests.count, 0)
        XCTAssertEqual(rawProvider.requests.count, 1)
        XCTAssertEqual(rawProvider.requests.first?.searchTerm, .keyword("Song"))
    }

    @MainActor
    func testLyricsKitProviderAutomaticUpdatesUseSearchFallbackForWeakDirectLyrics() async {
        let wrongLyrics = Lyrics(
            lines: [LyricsLine(content: "wrong line", position: 0)],
            idTags: [
                .title: "Qing Tian",
                .artist: "Mayday",
            ]
        )
        let fallbackLyrics = TimedLyrics(
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            album: "",
            duration: 200,
            service: "Kugou",
            lines: [TimedLyricLine(timestamp: 0, text: "right line")]
        )
        let candidate = LyricsSearchCandidate(
            id: "kugou|jay|lantingxu",
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            service: "Kugou",
            quality: 0.8,
            duration: 200,
            loadLyrics: { fallbackLyrics }
        )
        let rawProvider = StaticLyricsServiceProvider(lyrics: [wrongLyrics])
        let service = TestLyricsSearchService(results: [candidate])
        let provider = LyricsKitProvider(
            provider: rawProvider,
            searchServices: [service]
        )
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot(title: "Lan Ting Xu", artist: "Jay Chou")) {
            updates.append(lyrics)
        }

        XCTAssertEqual(updates, [fallbackLyrics])
        XCTAssertEqual(rawProvider.requests.count, 1)
        XCTAssertEqual(service.requests.count, 1)
    }

    @MainActor
    func testLyricsKitProviderAutomaticUpdatesUseSearchFallbackForDirectLyricsWithoutOriginalMetadata() async {
        let weakDirectLyrics = Lyrics(
            lines: [LyricsLine(content: "wrong line", position: 0)],
            idTags: [:]
        )
        let fallbackLyrics = TimedLyrics(
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            album: "",
            duration: 200,
            service: "Kugou",
            lines: [TimedLyricLine(timestamp: 0, text: "right line")]
        )
        let candidate = LyricsSearchCandidate(
            id: "kugou|jay|lantingxu",
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            service: "Kugou",
            quality: 0.8,
            duration: 200,
            loadLyrics: { fallbackLyrics }
        )
        let rawProvider = StaticLyricsServiceProvider(lyrics: [weakDirectLyrics])
        let service = TestLyricsSearchService(results: [candidate])
        let provider = LyricsKitProvider(
            provider: rawProvider,
            searchServices: [service]
        )
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot(title: "Lan Ting Xu", artist: "Jay Chou")) {
            updates.append(lyrics)
        }

        XCTAssertEqual(updates, [fallbackLyrics])
        XCTAssertEqual(rawProvider.requests.count, 1)
        XCTAssertEqual(service.requests.count, 1)
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

    @MainActor
    func testLyricsKitProviderSearchRanksCandidatesByQualityMatchAndDurationDifference() async {
        let lowerQuality = LyricsSearchCandidate(
            id: "lrclib|artist|song|lower",
            title: "Song",
            artist: "Artist",
            service: "LRCLIB",
            quality: 0.3,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "LRCLIB") }
        )
        let fartherDuration = LyricsSearchCandidate(
            id: "qq|artist|song|farther",
            title: "Song",
            artist: "Artist",
            service: "QQMusic",
            quality: 0.9,
            duration: 260,
            loadLyrics: { Self.makeLyrics(service: "QQMusic") }
        )
        let closerDuration = LyricsSearchCandidate(
            id: "netease|artist|song|closer",
            title: "Song",
            artist: "Artist",
            service: "NetEase",
            quality: 0.9,
            duration: 201,
            loadLyrics: { Self.makeLyrics(service: "NetEase") }
        )
        let weakerMatch = LyricsSearchCandidate(
            id: "kugou|artist|alternate|match",
            title: "Alternate Song",
            artist: "Artist",
            service: "Kugou",
            quality: 0.9,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "Kugou") }
        )
        let provider = LyricsKitProvider(
            searchServices: [
                TestLyricsSearchService(results: [lowerQuality, fartherDuration]),
                TestLyricsSearchService(results: [closerDuration, weakerMatch]),
            ]
        )

        let results = await provider.searchLyrics(
            title: "Song",
            artist: "Artist",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results, [closerDuration, fartherDuration, weakerMatch, lowerQuality])
    }

    @MainActor
    func testLyricsKitProviderSearchKeepsWeakMetadataResultBehindMetadataMatch() async {
        let wrongSong = LyricsSearchCandidate(
            id: "qq|artist|wrong|song",
            title: "Totally Different",
            artist: "Other Artist",
            service: "QQMusic",
            quality: 1.0,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "QQMusic") }
        )
        let matchedSong = LyricsSearchCandidate(
            id: "netease|artist|song",
            title: "Song",
            artist: "Artist",
            service: "NetEase",
            quality: 0.55,
            duration: 201,
            loadLyrics: { Self.makeLyrics(service: "NetEase") }
        )
        let provider = LyricsKitProvider(
            searchServices: [
                TestLyricsSearchService(results: [wrongSong, matchedSong]),
            ]
        )

        let results = await provider.searchLyrics(
            title: "Song",
            artist: "Artist",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results.first, matchedSong)
        XCTAssertTrue(results.contains(wrongSong))
        XCTAssertGreaterThan(
            try XCTUnwrap(results.firstIndex(of: wrongSong)),
            try XCTUnwrap(results.firstIndex(of: matchedSong))
        )
    }

    @MainActor
    func testLyricsKitProviderSearchRanksUnwantedAlternateVersionCandidatesLower() async {
        let karaokeLyrics = LyricsSearchCandidate(
            id: "qq|artist|song|karaoke",
            title: "Song (Instrumental)",
            artist: "Artist",
            service: "QQMusic",
            quality: 1.0,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "QQMusic") }
        )
        let normalLyrics = LyricsSearchCandidate(
            id: "netease|artist|song",
            title: "Song",
            artist: "Artist",
            service: "NetEase",
            quality: 0.55,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "NetEase") }
        )
        let provider = LyricsKitProvider(
            searchServices: [
                TestLyricsSearchService(results: [karaokeLyrics, normalLyrics]),
            ]
        )

        let results = await provider.searchLyrics(
            title: "Song",
            artist: "Artist",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results, [normalLyrics, karaokeLyrics])
    }

    @MainActor
    func testLyricsKitProviderAutomaticCandidateLoadSkipsMismatchedLoadedLyrics() async {
        let loadedWrongLyrics = TimedLyrics(
            title: "Qing Tian",
            artist: "Mayday",
            album: "",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "wrong line")]
        )
        let loadedRightLyrics = TimedLyrics(
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            album: "",
            duration: 200,
            service: "NetEase",
            lines: [TimedLyricLine(timestamp: 0, text: "right line")]
        )
        let misleadingCandidate = LyricsSearchCandidate(
            id: "qq|jay|lantingxu",
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            service: "QQMusic",
            quality: 1.0,
            duration: 200,
            loadLyrics: { loadedWrongLyrics }
        )
        let goodCandidate = LyricsSearchCandidate(
            id: "netease|jay|lantingxu",
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            service: "NetEase",
            quality: 0.8,
            duration: 200,
            loadLyrics: { loadedRightLyrics }
        )
        let provider = LyricsKitProvider(
            provider: EmptyLyricsServiceProvider(),
            searchServices: [
                TestLyricsSearchService(results: [misleadingCandidate, goodCandidate]),
            ]
        )
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot(title: "Lan Ting Xu", artist: "Jay Chou")) {
            updates.append(lyrics)
        }

        XCTAssertEqual(updates, [loadedRightLyrics])
    }

    @MainActor
    func testLyricsKitProviderAutomaticCandidateLoadDoesNotDropOnlyMismatchedLoadedLyrics() async {
        let loadedWrongLyrics = TimedLyrics(
            title: "Qing Tian",
            artist: "Mayday",
            album: "",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "wrong line")]
        )
        let onlyCandidate = LyricsSearchCandidate(
            id: "qq|jay|lantingxu",
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            service: "QQMusic",
            quality: 1.0,
            duration: 200,
            loadLyrics: { loadedWrongLyrics }
        )
        let provider = LyricsKitProvider(
            provider: EmptyLyricsServiceProvider(),
            searchServices: [
                TestLyricsSearchService(results: [onlyCandidate]),
            ]
        )
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot(title: "Lan Ting Xu", artist: "Jay Chou")) {
            updates.append(lyrics)
        }

        XCTAssertEqual(updates, [loadedWrongLyrics])
    }

    @MainActor
    func testLyricsKitProviderAutomaticCandidateLoadShowsBestLoadedLyricsFromSameBatch() async {
        let weakLoadedLyrics = TimedLyrics(
            title: "Lan Ting Xu",
            artist: "",
            album: "",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "weak line")]
        )
        let betterLoadedLyrics = TimedLyrics(
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            album: "",
            duration: 200,
            service: "Kugou",
            lines: [
                TimedLyricLine(
                    timestamp: 0,
                    text: "better line",
                    inlineTags: [
                        .init(index: 0, timeOffset: 0),
                        .init(index: 6, timeOffset: 1),
                    ]
                ),
            ]
        )
        let firstCandidate = LyricsSearchCandidate(
            id: "qq|jay|lantingxu",
            title: "Lan Ting Xu",
            artist: "Jay Chou",
            service: "QQMusic",
            quality: 1.0,
            duration: 200,
            loadLyrics: { weakLoadedLyrics }
        )
        let betterCandidate = LyricsSearchCandidate(
            id: "kugou|jay|lantingxu",
            title: "Lan Ting",
            artist: "",
            service: "Kugou",
            quality: 0.1,
            duration: 200,
            loadLyrics: { betterLoadedLyrics }
        )
        let provider = LyricsKitProvider(
            provider: EmptyLyricsServiceProvider(),
            searchServices: [
                TestLyricsSearchService(results: [firstCandidate, betterCandidate]),
            ]
        )
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot(title: "Lan Ting Xu", artist: "Jay Chou")) {
            updates.append(lyrics)
        }

        XCTAssertEqual(updates, [betterLoadedLyrics])
    }

    @MainActor
    func testLyricsKitProviderSearchPrefersInlineTimingWhenMetadataIsComparable() async {
        let plainLyrics = LyricsSearchCandidate(
            id: "lrclib|artist|song|plain",
            title: "Song",
            artist: "Artist",
            service: "LRCLIB",
            quality: 0.98,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "LRCLIB") }
        )
        let timedLyrics = LyricsSearchCandidate(
            id: "qq|artist|song|timed",
            title: "Song",
            artist: "Artist",
            service: "QQMusic",
            quality: 0.94,
            duration: 200,
            hasInlineTags: true,
            loadLyrics: { Self.makeLyrics(service: "QQMusic") }
        )
        let provider = LyricsKitProvider(
            searchServices: [
                TestLyricsSearchService(results: [plainLyrics, timedLyrics]),
            ]
        )

        let results = await provider.searchLyrics(
            title: "Song",
            artist: "Artist",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results.first, timedLyrics)
    }

    @MainActor
    func testLyricsKitProviderSearchKeepsHigherQualityMatchAbovePreferredSource() async {
        let lrclibLyrics = LyricsSearchCandidate(
            id: "lrclib|jay|lantingxu",
            title: "蘭亭序",
            artist: "周杰伦",
            service: "LRCLIB",
            quality: 1.0,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "LRCLIB") }
        )
        let kugouLyrics = LyricsSearchCandidate(
            id: "kugou|jay|lantingxu",
            title: "兰亭序",
            artist: "周杰伦",
            service: "Kugou",
            quality: 0.72,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "Kugou") }
        )
        let provider = LyricsKitProvider(
            searchServices: [
                TestLyricsSearchService(results: [lrclibLyrics, kugouLyrics]),
            ]
        )

        let results = await provider.searchLyrics(
            title: "蘭亭序",
            artist: "周杰伦",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results.first, lrclibLyrics)
    }

    @MainActor
    func testLyricsKitProviderSearchDoesNotLetSourcePriorityLiftWrongSong() async {
        let wrongPreferredLyrics = LyricsSearchCandidate(
            id: "kugou|wrong",
            title: "晴天",
            artist: "周杰伦",
            service: "Kugou",
            quality: 1.0,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "Kugou") }
        )
        let matchedLyrics = LyricsSearchCandidate(
            id: "lrclib|matched",
            title: "蘭亭序",
            artist: "周杰伦",
            service: "LRCLIB",
            quality: 0.55,
            duration: 200,
            loadLyrics: { Self.makeLyrics(service: "LRCLIB") }
        )
        let provider = LyricsKitProvider(
            searchServices: [
                TestLyricsSearchService(results: [wrongPreferredLyrics, matchedLyrics]),
            ]
        )

        let results = await provider.searchLyrics(
            title: "蘭亭序",
            artist: "周杰伦",
            duration: 200,
            limit: 10
        )

        XCTAssertEqual(results.first, matchedLyrics)
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
    func testCachedLyricsProviderReplacesWeakCachedLyricsWithBetterRemoteUpdate() async {
        let cachedLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "LRCLIB",
            lines: [TimedLyricLine(timestamp: 0, text: "cached plain")]
        )
        let remoteLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "QQMusic",
            lines: [
                TimedLyricLine(
                    timestamp: 0,
                    text: "remote timed",
                    inlineTags: [
                        .init(index: 0, timeOffset: 0),
                        .init(index: 6, timeOffset: 1),
                    ]
                ),
            ]
        )
        let cache = TestLyricsCache(loadedLyrics: cachedLyrics)
        let remote = TestLyricsProvider(result: remoteLyrics)
        let provider = CachedLyricsProvider(cache: cache, remoteProvider: remote)
        var updates: [TimedLyrics] = []

        for await lyrics in provider.lyricUpdates(for: Self.snapshot()) {
            updates.append(lyrics)
        }

        XCTAssertEqual(updates, [cachedLyrics, remoteLyrics])
        XCTAssertEqual(remote.requestedSnapshots.count, 1)
        XCTAssertEqual(cache.savedLyrics, remoteLyrics)
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

    private static func snapshot(
        title: String = "Song",
        artist: String = "Artist"
    ) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: title,
            artist: artist,
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

private final class EmptyLyricsServiceProvider: LyricsService.LyricsProvider, @unchecked Sendable {
    private(set) var requests: [LyricsSearchRequest] = []

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private final class StaticLyricsServiceProvider: LyricsService.LyricsProvider, @unchecked Sendable {
    private(set) var requests: [LyricsSearchRequest] = []
    private let lyrics: [Lyrics]

    init(lyrics: [Lyrics]) {
        self.lyrics = lyrics
    }

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        requests.append(request)
        let lyrics = lyrics
        return AsyncThrowingStream { continuation in
            for lyric in lyrics {
                lyric.metadata.request = request
                lyric.metadata.service = "LRCLIB"
                continuation.yield(lyric)
            }
            continuation.finish()
        }
    }
}

private final class TestLyricsCache: LyricsCaching {
    let directoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)

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

private final class TestLyricsSearchService: LyricsSearchServicing, @unchecked Sendable {
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
