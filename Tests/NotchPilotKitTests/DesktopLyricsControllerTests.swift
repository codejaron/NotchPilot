import XCTest
@testable import NotchPilotKit

final class DesktopLyricsControllerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        suiteName = "DesktopLyricsControllerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempHomeURL)
        suiteName = nil
        defaults = nil
        tempHomeURL = nil
    }

    @MainActor
    func testControllerLoadsLyricsForActivePlayback() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = StreamingDesktopLyricsControllerTestProvider()
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0, text: "line 1"),
                TimedLyricLine(timestamp: 15, text: "line 2"),
            ]
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 16, isPlaying: true))
        await Self.waitForStreamingProviderRequest(provider)
        await provider.yield(lyrics)
        await Self.waitForCurrentLine("line 2", controller: controller)

        XCTAssertEqual(provider.requestedSnapshots.count, 1)
        XCTAssertTrue(controller.presentation.isVisible)
        XCTAssertEqual(controller.presentation.currentLine, "line 2")
    }

    @MainActor
    func testControllerSearchesLyricsWhenArtistMetadataIsMissing() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = StreamingDesktopLyricsControllerTestProvider()
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [TimedLyricLine(timestamp: 0, text: "line")]
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(
            Self.snapshot(
                bundleIdentifier: "com.spotify.client",
                title: "Song",
                artist: "",
                currentTime: 1,
                isPlaying: true
            )
        )
        await Self.waitForStreamingProviderRequest(provider)
        await provider.yield(lyrics)
        await Self.waitForCurrentLine("line", controller: controller)

        XCTAssertEqual(provider.requestedSnapshots.count, 1)
        XCTAssertEqual(controller.presentation.currentLine, "line")
    }

    @MainActor
    func testControllerShowsFirstLyricsUpdateThenReplacesWithLaterUpdate() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = StreamingDesktopLyricsControllerTestProvider()
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )
        let firstLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "first usable")]
        )
        let replacementLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "NetEase",
            lines: [TimedLyricLine(timestamp: 0, text: "better replacement")]
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 5, isPlaying: true))
        await Self.waitForStreamingProviderRequest(provider)

        await provider.yield(firstLyrics)
        await Self.flushMainActorTasks()

        XCTAssertEqual(controller.presentation.currentLine, "first usable")

        await provider.yield(replacementLyrics)
        await Self.flushMainActorTasks()

        XCTAssertEqual(controller.presentation.currentLine, "better replacement")
        XCTAssertEqual(provider.requestedSnapshots.count, 1)
    }

    @MainActor
    func testControllerUsesSnapshotEstimatedPlaybackTimeWhenResolvingPresentation() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = StreamingDesktopLyricsControllerTestProvider()
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0, text: "line 1"),
                TimedLyricLine(timestamp: 15, text: "line 2"),
            ]
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 16, isPlaying: true))
        await Self.waitForStreamingProviderRequest(provider)
        await provider.yield(lyrics)
        await Self.waitForCurrentLine("line 2", controller: controller)

        XCTAssertEqual(controller.presentation.currentLine, "line 2")
    }

    @MainActor
    func testControllerShowsFirstLineBeforeFirstTimestampAfterLyricsLoad() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = StreamingDesktopLyricsControllerTestProvider()
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0.05, text: "first line"),
                TimedLyricLine(timestamp: 1, text: "second line"),
            ]
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 0, isPlaying: true))
        await Self.waitForStreamingProviderRequest(provider)
        await provider.yield(lyrics)
        await Self.flushMainActorTasks()

        XCTAssertTrue(controller.presentation.isVisible)
        XCTAssertEqual(controller.presentation.currentLine, "first line")

        try? await Task.sleep(for: .milliseconds(120))
        await Self.flushMainActorTasks()

        XCTAssertEqual(controller.presentation.currentLine, "first line")
    }

    @MainActor
    func testControllerHidesWhenPlaybackPauses() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = DesktopLyricsControllerTestProvider(
            result: TimedLyrics(
                title: "Song",
                artist: "Artist",
                album: "Album",
                duration: 200,
                service: "cache",
                lines: [TimedLyricLine(timestamp: 0, text: "line 1")]
            )
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 5, isPlaying: true))
        await Self.flushMainActorTasks()
        controller.handlePlaybackState(Self.snapshot(currentTime: 5, isPlaying: false))

        XCTAssertFalse(controller.presentation.isVisible)
        XCTAssertNil(controller.presentation.currentLine)
    }

    @MainActor
    func testControllerKeepsLyricsHiddenWhenPlaybackSwitchesToIneligibleSource() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = StreamingDesktopLyricsControllerTestProvider()
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0, text: "line 1"),
                TimedLyricLine(timestamp: 15, text: "line 2"),
            ]
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 16, isPlaying: true))
        await Self.waitForStreamingProviderRequest(provider)
        await provider.yield(lyrics)
        await Self.waitForCurrentLine("line 2", controller: controller)
        XCTAssertTrue(controller.presentation.isVisible)

        controller.handlePlaybackState(
            Self.snapshot(
                bundleIdentifier: "com.google.Chrome",
                title: "Video Title",
                artist: "Chrome",
                currentTime: 20,
                isPlaying: true
            )
        )
        XCTAssertFalse(controller.presentation.isVisible)

        controller.refreshPresentation(at: Date(timeIntervalSince1970: 120))

        XCTAssertFalse(controller.presentation.isVisible)
        XCTAssertNil(controller.presentation.currentLine)
        XCTAssertEqual(provider.requestedSnapshots.count, 1)
    }

    @MainActor
    func testControllerSkipsLookupWhenDesktopLyricsDisabled() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = false
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = DesktopLyricsControllerTestProvider(
            result: TimedLyrics(
                title: "Song",
                artist: "Artist",
                album: "Album",
                duration: 200,
                service: "cache",
                lines: [TimedLyricLine(timestamp: 0, text: "line 1")]
            )
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 5, isPlaying: true))
        await Self.flushMainActorTasks()

        XCTAssertEqual(provider.requestedSnapshots.count, 0)
        XCTAssertFalse(controller.presentation.isVisible)
    }

    @MainActor
    func testControllerSkipsLookupForIgnoredTrack() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        ignoredTrackStore.insert(LyricsTrackKey(snapshot: Self.activeSnapshot(currentTime: 5, isPlaying: true)))
        let cache = TestControllerLyricsCache()
        let provider = DesktopLyricsControllerTestProvider(
            result: TimedLyrics(
                title: "Song",
                artist: "Artist",
                album: "Album",
                duration: 200,
                service: "cache",
                lines: [TimedLyricLine(timestamp: 0, text: "line 1")]
            )
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 5, isPlaying: true))
        await Self.flushMainActorTasks()

        XCTAssertEqual(provider.requestedSnapshots.count, 0)
        XCTAssertFalse(controller.presentation.isVisible)
    }

    @MainActor
    func testIgnoringCurrentTrackHidesLyricsAndDeletesCachedFile() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = DesktopLyricsControllerTestProvider(
            result: TimedLyrics(
                title: "Song",
                artist: "Artist",
                album: "Album",
                duration: 200,
                service: "cache",
                lines: [TimedLyricLine(timestamp: 0, text: "line 1")]
            )
        )
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )

        controller.handlePlaybackState(Self.snapshot(currentTime: 5, isPlaying: true))
        await Self.flushMainActorTasks()
        controller.ignoreCurrentTrackLyrics()

        XCTAssertFalse(controller.presentation.isVisible)
        XCTAssertEqual(cache.removedKeys.count, 1)
        XCTAssertEqual(ignoredTrackStore.insertedKeys.count, 1)
    }

    @MainActor
    func testApplyingLyricsOverrideSavesLyricsAndClearsIgnoredFlag() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let provider = DesktopLyricsControllerTestProvider(result: nil)
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )
        let bindingSnapshot = Self.activeSnapshot(currentTime: 5, isPlaying: true)
        let lyrics = TimedLyrics(
            title: "Different Search Title",
            artist: "Different Search Artist",
            album: "",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "line 1")]
        )

        ignoredTrackStore.insert(LyricsTrackKey(snapshot: bindingSnapshot))
        controller.applyLyricsOverride(lyrics, for: bindingSnapshot)

        XCTAssertEqual(cache.savedEntries.count, 1)
        XCTAssertEqual(cache.savedEntries.first?.key, LyricsTrackKey(snapshot: bindingSnapshot))
        XCTAssertEqual(cache.savedEntries.first?.lyrics, lyrics)
        XCTAssertEqual(ignoredTrackStore.removedKeys, [LyricsTrackKey(snapshot: bindingSnapshot)])
    }

    @MainActor
    func testPreviewingLyricsOverrideUpdatesKTVWithoutSavingAndCanCancel() async {
        let store = makeSettingsStore()
        store.mediaPlaybackEnabled = true
        store.desktopLyricsEnabled = true
        let ignoredTrackStore = TestIgnoredLyricsStore()
        let cache = TestControllerLyricsCache()
        let originalLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [TimedLyricLine(timestamp: 0, text: "original line")]
        )
        let previewLyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "QQMusic",
            lines: [TimedLyricLine(timestamp: 0, text: "preview line")]
        )
        let provider = StreamingDesktopLyricsControllerTestProvider()
        let controller = DesktopLyricsController(
            settingsStore: store,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )
        let bindingSnapshot = Self.activeSnapshot(currentTime: 5, isPlaying: true)

        controller.handlePlaybackState(.active(bindingSnapshot))
        await Self.waitForStreamingProviderRequest(provider)
        await provider.yield(originalLyrics)
        await Self.flushMainActorTasks()
        controller.previewLyricsOverride(previewLyrics, for: bindingSnapshot)

        XCTAssertEqual(controller.presentation.currentLine, "preview line")
        XCTAssertTrue(cache.savedEntries.isEmpty)

        controller.cancelLyricsOverridePreview(for: bindingSnapshot)

        XCTAssertEqual(controller.presentation.currentLine, "original line")
        XCTAssertTrue(cache.savedEntries.isEmpty)
    }

    private static func flushMainActorTasks() async {
        for _ in 0 ..< 5 {
            await Task.yield()
        }
    }

    @MainActor
    private static func waitForCurrentLine(
        _ line: String?,
        controller: DesktopLyricsController
    ) async {
        for _ in 0 ..< 100 {
            if controller.presentation.currentLine == line {
                return
            }
            await Task.yield()
        }
    }

    @MainActor
    private static func waitForStreamingProviderRequest(
        _ provider: StreamingDesktopLyricsControllerTestProvider
    ) async {
        for _ in 0 ..< 20 {
            if provider.requestedSnapshots.isEmpty == false, provider.isReady {
                return
            }
            await Task.yield()
        }
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
    }

    private static func snapshot(currentTime: TimeInterval, isPlaying: Bool) -> MediaPlaybackState {
        .active(activeSnapshot(currentTime: currentTime, isPlaying: isPlaying))
    }

    private static func snapshot(
        bundleIdentifier: String,
        title: String,
        artist: String,
        currentTime: TimeInterval,
        isPlaying: Bool
    ) -> MediaPlaybackState {
        .active(
            activeSnapshot(
                bundleIdentifier: bundleIdentifier,
                title: title,
                artist: artist,
                currentTime: currentTime,
                isPlaying: isPlaying
            )
        )
    }

    private static func activeSnapshot(
        bundleIdentifier: String = "com.spotify.client",
        title: String = "Song",
        artist: String = "Artist",
        currentTime: TimeInterval,
        isPlaying: Bool,
        lastUpdated: Date = Date()
    ) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: .fromBundleIdentifier(bundleIdentifier),
            title: title,
            artist: artist,
            album: "Album",
            artworkData: nil,
            currentTime: currentTime,
            duration: 200,
            playbackRate: 1,
            isPlaying: isPlaying,
            lastUpdated: lastUpdated
        )
    }
}

@MainActor
private final class DesktopLyricsControllerTestProvider: LyricsProviding {
    let result: TimedLyrics?
    private(set) var requestedSnapshots: [MediaPlaybackSnapshot] = []

    init(result: TimedLyrics?) {
        self.result = result
    }

    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        requestedSnapshots.append(snapshot)
        return result
    }

    func lyricUpdates(for snapshot: MediaPlaybackSnapshot) -> AsyncStream<TimedLyrics> {
        requestedSnapshots.append(snapshot)
        return AsyncStream { continuation in
            let result = result
            let task = Task { @MainActor in
                if let result {
                    continuation.yield(result)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

@MainActor
private final class StreamingDesktopLyricsControllerTestProvider: LyricsProviding {
    private var continuation: AsyncStream<TimedLyrics>.Continuation?
    private(set) var isReady = false
    private(set) var requestedSnapshots: [MediaPlaybackSnapshot] = []

    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        for await lyrics in lyricUpdates(for: snapshot) {
            return lyrics
        }
        return nil
    }

    func lyricUpdates(for snapshot: MediaPlaybackSnapshot) -> AsyncStream<TimedLyrics> {
        requestedSnapshots.append(snapshot)
        return AsyncStream { continuation in
            self.continuation = continuation
            self.isReady = true
        }
    }

    func yield(_ lyrics: TimedLyrics) async {
        for _ in 0 ..< 100 {
            if let continuation {
                continuation.yield(lyrics)
                return
            }
            await Task.yield()
        }
    }
}

private final class TestIgnoredLyricsStore: LyricsTrackIgnoring {
    private(set) var insertedKeys: [LyricsTrackKey] = []
    private(set) var removedKeys: [LyricsTrackKey] = []
    private var keys: Set<LyricsTrackKey> = []

    func contains(_ key: LyricsTrackKey) -> Bool {
        keys.contains(key)
    }

    func insert(_ key: LyricsTrackKey) {
        insertedKeys.append(key)
        keys.insert(key)
    }

    func remove(_ key: LyricsTrackKey) {
        removedKeys.append(key)
        keys.remove(key)
    }
}

private final class TestControllerLyricsCache: LyricsCaching {
    let directoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)

    private(set) var removedKeys: [LyricsTrackKey] = []
    private(set) var savedEntries: [(key: LyricsTrackKey, lyrics: TimedLyrics)] = []

    func loadLyrics(for key: LyricsTrackKey) -> TimedLyrics? {
        nil
    }

    func saveLyrics(_ lyrics: TimedLyrics, for key: LyricsTrackKey) throws {
        savedEntries.append((key: key, lyrics: lyrics))
    }

    func fileURL(for key: LyricsTrackKey) -> URL {
        URL(fileURLWithPath: "/tmp/\(key.cacheFileName)")
    }

    func removeLyrics(for key: LyricsTrackKey) throws {
        removedKeys.append(key)
    }
}
