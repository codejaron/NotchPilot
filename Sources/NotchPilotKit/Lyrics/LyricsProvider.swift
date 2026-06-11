import Foundation
import LyricsKit
@preconcurrency import LyricsService

@MainActor
protocol LyricsProviding: AnyObject {
    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics?
    func lyricUpdates(for snapshot: MediaPlaybackSnapshot) -> AsyncStream<TimedLyrics>
}

@MainActor
protocol LyricsSearching: AnyObject {
    func searchLyrics(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int
    ) async -> [LyricsSearchCandidate]
    func searchLyricsUpdates(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int
    ) -> AsyncStream<[LyricsSearchCandidate]>
}

protocol LyricsCaching: AnyObject {
    var directoryURL: URL { get }

    func loadLyrics(for key: LyricsTrackKey) -> TimedLyrics?
    func saveLyrics(_ lyrics: TimedLyrics, for key: LyricsTrackKey) throws
    func fileURL(for key: LyricsTrackKey) -> URL
    func removeLyrics(for key: LyricsTrackKey) throws
}

extension LyricsSearchRequest: @retroactive @unchecked Sendable {}
extension Lyrics: @retroactive @unchecked Sendable {}

extension LyricsProviding {
    func lyricUpdates(for snapshot: MediaPlaybackSnapshot) -> AsyncStream<TimedLyrics> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                if let lyrics = await self.lyrics(for: snapshot) {
                    continuation.yield(lyrics)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

extension LyricsSearching {
    func searchLyricsUpdates(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int
    ) -> AsyncStream<[LyricsSearchCandidate]> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let results = await self.searchLyrics(
                    title: title,
                    artist: artist,
                    duration: duration,
                    limit: limit
                )
                continuation.yield(results)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

final class LyricsCache: LyricsCaching {
    let directoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    convenience init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.init(
            directoryURL: homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("NotchPilot", isDirectory: true)
                .appendingPathComponent("LyricsCache", isDirectory: true),
            fileManager: fileManager
        )
    }

    func loadLyrics(for key: LyricsTrackKey) -> TimedLyrics? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(TimedLyrics.self, from: data)
    }

    func saveLyrics(_ lyrics: TimedLyrics, for key: LyricsTrackKey) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(lyrics)
        try data.write(to: fileURL(for: key))
    }

    func fileURL(for key: LyricsTrackKey) -> URL {
        directoryURL.appendingPathComponent(key.cacheFileName, isDirectory: false)
    }

    func removeLyrics(for key: LyricsTrackKey) throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}

final class CachedLyricsProvider: LyricsProviding {
    private let cache: LyricsCaching
    private let remoteProvider: LyricsProviding

    init(cache: LyricsCaching, remoteProvider: LyricsProviding) {
        self.cache = cache
        self.remoteProvider = remoteProvider
    }

    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        let key = LyricsTrackKey(snapshot: snapshot)
        if let cached = cache.loadLyrics(for: key) {
            return cached
        }

        for await lyrics in lyricUpdates(for: snapshot) {
            return lyrics
        }

        return nil
    }

    func lyricUpdates(for snapshot: MediaPlaybackSnapshot) -> AsyncStream<TimedLyrics> {
        let key = LyricsTrackKey(snapshot: snapshot)

        return AsyncStream { continuation in
            let cached = cache.loadLyrics(for: key)
            let task = Task { @MainActor in
                var bestPreference: LyricsCandidatePreference?
                if let cached {
                    bestPreference = Self.preference(for: cached, snapshot: snapshot)
                    continuation.yield(cached)
                }

                for await remote in remoteProvider.lyricUpdates(for: snapshot) {
                    guard Task.isCancelled == false else {
                        break
                    }

                    let remotePreference = Self.preference(for: remote, snapshot: snapshot)
                    if let bestPreference,
                       LyricsCandidatePreference.prefers(bestPreference, over: remotePreference) {
                        continue
                    }

                    bestPreference = remotePreference
                    try? cache.saveLyrics(remote, for: key)
                    continuation.yield(remote)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func preference(
        for lyrics: TimedLyrics,
        snapshot: MediaPlaybackSnapshot
    ) -> LyricsCandidatePreference {
        LyricsCandidatePreference.make(
            lyrics: lyrics,
            baseQuality: inferredQuality(for: lyrics),
            requestTitle: snapshot.title,
            requestArtist: snapshot.artist,
            duration: snapshot.duration
        )
    }

    private static func inferredQuality(for lyrics: TimedLyrics) -> Double {
        if lyrics.hasInlineTags {
            return 0.9
        }

        switch lyrics.service.lowercased() {
        case "qqmusic", "kugou", "netease", "musixmatch":
            return 0.74
        default:
            return 0.62
        }
    }
}

private final class ConcurrentLyricsProviderBox: @unchecked Sendable {
    let provider: LyricsService.LyricsProvider

    init(provider: LyricsService.LyricsProvider) {
        self.provider = provider
    }
}

private final class ConcurrentLyricsProvider: LyricsService.LyricsProvider {
    private let providers: [ConcurrentLyricsProviderBox]

    init(services: [LyricsProviders.Service]) {
        self.providers = services.map { ConcurrentLyricsProviderBox(provider: $0.create()) }
    }

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            let providers = providers
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for providerBox in providers {
                        group.addTask {
                            do {
                                for try await lyric in providerBox.provider.lyrics(for: request) {
                                    guard Task.isCancelled == false else { break }
                                    continuation.yield(lyric)
                                }
                            } catch {}
                        }
                    }
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
final class LyricsKitProvider: LyricsProviding, LyricsSearching {
    private let provider: LyricsService.LyricsProvider
    private let searchServices: [any LyricsSearchServicing]
    private static let immediateSelectionScore = 0.75

    private struct SelectedLyricsUpdate {
        let lyrics: TimedLyrics
        let preference: LyricsCandidatePreference
    }

    init(
        provider: LyricsService.LyricsProvider? = nil,
        searchServices: [any LyricsSearchServicing]? = nil
    ) {
        let provider = provider ?? ConcurrentLyricsProvider(services: LyricsKitServiceConfiguration.defaultServices)
        self.provider = provider
        self.searchServices = searchServices ?? LyricsKitSearchServices.default()
    }

    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        for await lyrics in lyricUpdates(for: snapshot) {
            return lyrics
        }

        return nil
    }

    func lyricUpdates(for snapshot: MediaPlaybackSnapshot) -> AsyncStream<TimedLyrics> {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard title.isEmpty == false || artist.isEmpty == false else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                var bestPreference: LyricsCandidatePreference?
                var deferredUpdate: SelectedLyricsUpdate?
                var didYieldLyrics = false

                for await update in directLyricUpdates(for: snapshot) {
                    guard Task.isCancelled == false else {
                        break
                    }

                    if update.preference.score < Self.immediateSelectionScore {
                        if let current = deferredUpdate,
                           LyricsCandidatePreference.prefers(current.preference, over: update.preference) {
                            continue
                        }
                        deferredUpdate = update
                        continue
                    }

                    bestPreference = update.preference
                    didYieldLyrics = true
                    continuation.yield(update.lyrics)
                }

                let bestAvailablePreference = bestPreference ?? deferredUpdate?.preference
                let shouldSearchCandidates = bestAvailablePreference.map { preference in
                    preference.score < Self.immediateSelectionScore
                } ?? true

                if Task.isCancelled == false,
                   searchServices.isEmpty == false,
                   shouldSearchCandidates {
                    for await update in candidateLyricUpdates(
                        title: title,
                        artist: artist,
                        duration: snapshot.duration,
                        limit: 8,
                        initialPreference: bestAvailablePreference
                    ) {
                        guard Task.isCancelled == false else {
                            break
                        }
                        bestPreference = update.preference
                        didYieldLyrics = true
                        continuation.yield(update.lyrics)
                    }
                }

                if didYieldLyrics == false, let deferredUpdate {
                    continuation.yield(deferredUpdate.lyrics)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func candidateLyricUpdates(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int,
        initialPreference: LyricsCandidatePreference?
    ) -> AsyncStream<SelectedLyricsUpdate> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var bestPreference = initialPreference
                var loadedCandidateIDs: Set<String> = []

                for await candidates in searchLyricsUpdates(
                    title: title,
                    artist: artist,
                    duration: duration,
                    limit: limit
                ) {
                    guard Task.isCancelled == false else {
                        break
                    }

                    var batchSelection: SelectedLyricsUpdate?

                    for candidate in candidates where loadedCandidateIDs.contains(candidate.id) == false {
                        loadedCandidateIDs.insert(candidate.id)

                        guard let timedLyrics = try? await candidate.loadLyrics() else {
                            continue
                        }

                        let loadedPreference = LyricsCandidatePreference.make(
                            lyrics: timedLyrics,
                            baseQuality: candidate.quality,
                            requestTitle: title,
                            requestArtist: artist,
                            duration: duration
                        )

                        if let batchSelection = batchSelection,
                           LyricsCandidatePreference.prefers(batchSelection.preference, over: loadedPreference) {
                            continue
                        }

                        if let bestPreference,
                           LyricsCandidatePreference.prefers(bestPreference, over: loadedPreference) {
                            continue
                        }

                        batchSelection = SelectedLyricsUpdate(
                            lyrics: timedLyrics,
                            preference: loadedPreference
                        )
                    }

                    if let batchSelection {
                        bestPreference = batchSelection.preference
                        continuation.yield(batchSelection)
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func directLyricUpdates(for snapshot: MediaPlaybackSnapshot) -> AsyncStream<SelectedLyricsUpdate> {
        guard let request = Self.makeRequest(for: snapshot) else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let requestedMetadata = Self.metadata(for: request)
                var bestPreference: LyricsCandidatePreference?
                var windowStart: Date?
                let priorityWindow: TimeInterval = 5

                do {
                    for try await lyric in provider.lyrics(for: request) {
                        guard Task.isCancelled == false else {
                            break
                        }

                        if let start = windowStart,
                           Date().timeIntervalSince(start) > priorityWindow {
                            break
                        }

                        let rawMetadata = Self.metadata(for: lyric)
                        guard let timedLyrics = TimedLyrics(
                            lyricsKitLyrics: lyric,
                            service: lyric.metadata.service ?? "LyricsKit",
                            fallbackTitle: requestedMetadata.title,
                            fallbackArtist: requestedMetadata.artist
                        ) else {
                            continue
                        }

                        let preference = LyricsCandidatePreference.make(
                            title: rawMetadata.title,
                            artist: rawMetadata.artist,
                            service: timedLyrics.service,
                            baseQuality: lyric.quality,
                            candidateDuration: timedLyrics.duration,
                            hasInlineTags: timedLyrics.hasInlineTags,
                            requestTitle: requestedMetadata.title,
                            requestArtist: requestedMetadata.artist,
                            duration: snapshot.duration
                        )

                        if let currentPreference = bestPreference,
                           LyricsCandidatePreference.prefers(currentPreference, over: preference) {
                            continue
                        }

                        bestPreference = preference
                        if windowStart == nil {
                            windowStart = Date()
                        }
                        continuation.yield(
                            SelectedLyricsUpdate(
                                lyrics: timedLyrics,
                                preference: preference
                            )
                        )
                    }
                } catch {}

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func metadata(for lyrics: Lyrics) -> (title: String, artist: String) {
        (
            lyrics.idTags[.title]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            lyrics.idTags[.artist]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private static func makeRequest(for snapshot: MediaPlaybackSnapshot) -> LyricsSearchRequest? {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false || artist.isEmpty == false else { return nil }
        return LyricsSearchRequest(
            searchTerm: artist.isEmpty
                ? .keyword(title)
                : .info(title: title, artist: artist),
            duration: snapshot.duration ?? 0,
            limit: 5
        )
    }

    private static func metadata(for request: LyricsSearchRequest) -> (title: String, artist: String) {
        switch request.searchTerm {
        case let .info(title, artist):
            return (title, artist)
        case let .keyword(keyword):
            return (keyword, "")
        }
    }

    func searchLyrics(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int = 40
    ) async -> [LyricsSearchCandidate] {
        var latestResults: [LyricsSearchCandidate] = []
        for await results in searchLyricsUpdates(
            title: title,
            artist: artist,
            duration: duration,
            limit: limit
        ) {
            latestResults = results
        }

        return latestResults
    }

    func searchLyricsUpdates(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int = 40
    ) -> AsyncStream<[LyricsSearchCandidate]> {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedTitle.isEmpty == false || normalizedArtist.isEmpty == false else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        let request = LyricsSearchRequest(
            searchTerm: normalizedArtist.isEmpty
                ? .keyword(normalizedTitle)
                : .info(title: normalizedTitle, artist: normalizedArtist),
            duration: duration ?? 0,
            limit: max(1, min(limit, 8))
        )

        let perServiceLimit = max(1, min(limit, 8))
        let services = searchServices

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                var collectedResults: [LyricsSearchCandidate] = []
                await withTaskGroup(of: [LyricsSearchCandidate].self) { group in
                    for service in services {
                        group.addTask {
                            await service.searchCandidates(
                                for: request,
                                limit: perServiceLimit
                            )
                        }
                    }

                    for await candidates in group {
                        guard Task.isCancelled == false else {
                            break
                        }

                        collectedResults.append(contentsOf: candidates)
                        let rankedResults = LyricsSearchCandidateRanker.ranked(
                            collectedResults,
                            requestTitle: normalizedTitle,
                            requestArtist: normalizedArtist,
                            duration: duration,
                            limit: limit
                        )
                        continuation.yield(rankedResults)
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

}
