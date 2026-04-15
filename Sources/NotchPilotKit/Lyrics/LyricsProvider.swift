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

        guard let remoteLyrics = await remoteProvider.lyrics(for: snapshot) else {
            return nil
        }

        try? cache.saveLyrics(remoteLyrics, for: key)
        return remoteLyrics
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
        let provider = provider ?? LyricsProviders.Group(service: [
            .qq,
            .kugou,
            .netease,
            .musixmatch,
            .lrclib,
        ])
        self.provider = provider
        self.searchServices = searchServices ?? LyricsKitSearchServices.default()
    }

    func lyrics(for snapshot: MediaPlaybackSnapshot) async -> TimedLyrics? {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard title.isEmpty == false, artist.isEmpty == false else {
            return nil
        }

        let request = LyricsSearchRequest(
            searchTerm: .info(title: title, artist: artist),
            duration: snapshot.duration ?? 0
        )

        do {
            for try await lyric in provider.lyrics(for: request) {
                guard let timedLyrics = TimedLyrics(
                    lyricsKitLyrics: lyric,
                    service: lyric.metadata.service ?? "LyricsKit"
                ),
                      matchesCandidate(timedLyrics, snapshot: snapshot) else {
                    continue
                }
                return timedLyrics
            }
        } catch {
            return nil
        }

        return nil
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
            limit: max(limit, 20)
        )

        var seenIdentifiers: Set<String> = []
        var results: [LyricsSearchCandidate] = []
        let perServiceLimit = max(12, min(limit, 20))

        for service in searchServices {
            let candidates = await service.searchCandidates(
                for: request,
                limit: perServiceLimit
            )

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

    private func matchesCandidate(_ candidate: TimedLyrics, snapshot: MediaPlaybackSnapshot) -> Bool {
        guard LyricsTrackKey.normalize(candidate.title) == LyricsTrackKey.normalize(snapshot.title),
              LyricsTrackKey.normalize(candidate.artist) == LyricsTrackKey.normalize(snapshot.artist) else {
            return false
        }

        guard let candidateDuration = candidate.duration,
              let snapshotDuration = snapshot.duration else {
            return true
        }

        return abs(candidateDuration - snapshotDuration) <= 2
    }
}
