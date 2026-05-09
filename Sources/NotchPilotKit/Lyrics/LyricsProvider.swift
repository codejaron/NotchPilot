import Foundation
import LyricsKit
@preconcurrency import LyricsService

@MainActor
protocol LyricsProviding: AnyObject {
    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics?
}

@MainActor
protocol LyricsSearching: AnyObject {
    func searchLyrics(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int
    ) async -> [LyricsSearchCandidate]
}

protocol LyricsCaching: AnyObject {
    func loadLyrics(for key: LyricsTrackKey) -> TimedLyrics?
    func saveLyrics(_ lyrics: TimedLyrics, for key: LyricsTrackKey) throws
    func fileURL(for key: LyricsTrackKey) -> URL
    func removeLyrics(for key: LyricsTrackKey) throws
}

extension LyricsSearchRequest: @retroactive @unchecked Sendable {}
extension Lyrics: @retroactive @unchecked Sendable {}

final class LyricsCache: LyricsCaching {
    private let directoryURL: URL
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

        let remote = await remoteProvider.lyrics(for: snapshot)
        if let remote {
            try? cache.saveLyrics(remote, for: key)
        }

        return remote
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

    init(
        provider: LyricsService.LyricsProvider? = nil,
        searchServices: [any LyricsSearchServicing]? = nil
    ) {
        let provider = provider ?? ConcurrentLyricsProvider(services: LyricsKitServiceConfiguration.defaultServices)
        self.provider = provider
        self.searchServices = searchServices ?? LyricsKitSearchServices.default()
    }

    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        guard let request = Self.makeRequest(for: snapshot) else {
            return nil
        }

        var best: Lyrics?
        var windowStart: Date?
        let priorityWindow: TimeInterval = 3

        do {
            for try await lyric in provider.lyrics(for: request) {
                guard Task.isCancelled == false else { break }

                if let start = windowStart,
                   Date().timeIntervalSince(start) > priorityWindow {
                    break
                }

                if let current = best, !Self.hasHigherPriority(lyric, over: current) {
                    continue
                }

                best = lyric
                if windowStart == nil {
                    windowStart = Date()
                }

                if lyric.metadata.attachmentTags.contains(.timetag) {
                    break
                }
            }
        } catch {}

        guard let best else { return nil }
        return TimedLyrics(
            lyricsKitLyrics: best,
            service: best.metadata.service ?? "LyricsKit"
        )
    }

    private static func hasHigherPriority(_ new: Lyrics, over existing: Lyrics) -> Bool {
        return new.quality > existing.quality
    }

    private static func makeRequest(for snapshot: MediaPlaybackSnapshot) -> LyricsSearchRequest? {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return LyricsSearchRequest(
            searchTerm: .info(title: title, artist: artist),
            duration: snapshot.duration ?? 0,
            limit: 5
        )
    }

    func searchLyrics(
        title: String,
        artist: String,
        duration: TimeInterval?,
        limit: Int = 40
    ) async -> [LyricsSearchCandidate] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedTitle.isEmpty == false || normalizedArtist.isEmpty == false else {
            return []
        }

        let request = LyricsSearchRequest(
            searchTerm: normalizedArtist.isEmpty
                ? .keyword(normalizedTitle)
                : .info(title: normalizedTitle, artist: normalizedArtist),
            duration: duration ?? 0,
            limit: max(1, min(limit, 8))
        )

        var seenIdentifiers: Set<String> = []
        var results: [LyricsSearchCandidate] = []
        let perServiceLimit = max(1, min(limit, 8))
        let serviceResults = await withTaskGroup(of: (Int, [LyricsSearchCandidate]).self) { group in
            for (index, service) in searchServices.enumerated() {
                group.addTask {
                    (
                        index,
                        await service.searchCandidates(
                            for: request,
                            limit: perServiceLimit
                        )
                    )
                }
            }

            var collected = Array(repeating: [LyricsSearchCandidate](), count: searchServices.count)
            for await (index, candidates) in group {
                collected[index] = candidates
            }
            return collected
        }

        for candidates in serviceResults {
            for candidate in candidates {
                let identifier = [
                    candidate.service,
                    LyricsTrackKey.normalize(candidate.artist),
                    LyricsTrackKey.normalize(candidate.title),
                ].joined(separator: "|")

                guard seenIdentifiers.insert(identifier).inserted else {
                    continue
                }

                results.append(candidate)
                if results.count >= limit {
                    break
                }
            }

            if results.count >= limit {
                break
            }
        }

        return results
    }

}
