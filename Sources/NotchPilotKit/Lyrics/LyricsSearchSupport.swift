import Foundation
import LyricsKit
@preconcurrency import LyricsService

struct LyricsSearchCandidate: Identifiable {
    let id: String
    let title: String
    let artist: String
    let service: String

    private let loadLyricsHandler: @Sendable () async throws -> TimedLyrics

    init(
        id: String,
        title: String,
        artist: String,
        service: String,
        loadLyrics: @escaping @Sendable () async throws -> TimedLyrics
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.service = service
        self.loadLyricsHandler = loadLyrics
    }

    init(lyrics: TimedLyrics) {
        self.init(
            id: [
                lyrics.service,
                LyricsTrackKey.normalize(lyrics.artist),
                LyricsTrackKey.normalize(lyrics.title),
                lyrics.duration.map { String(Int($0.rounded())) } ?? "",
            ].joined(separator: "|"),
            title: lyrics.title,
            artist: lyrics.artist,
            service: lyrics.service,
            loadLyrics: { lyrics }
        )
    }

    @MainActor
    func loadLyrics() async throws -> TimedLyrics {
        try await loadLyricsHandler()
    }
}

extension LyricsSearchCandidate: Sendable {}

extension LyricsSearchCandidate: Equatable {
    static func == (lhs: LyricsSearchCandidate, rhs: LyricsSearchCandidate) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.artist == rhs.artist &&
            lhs.service == rhs.service
    }
}

protocol LyricsSearchServicing: Sendable {
    func searchCandidates(
        for request: LyricsSearchRequest,
        limit: Int
    ) async -> [LyricsSearchCandidate]
}

private struct AnyLyricsSearchService: LyricsSearchServicing {
    private let searchHandler: @Sendable (LyricsSearchRequest, Int) async -> [LyricsSearchCandidate]

    init(
        _ searchHandler: @escaping @Sendable (LyricsSearchRequest, Int) async -> [LyricsSearchCandidate]
    ) {
        self.searchHandler = searchHandler
    }

    func searchCandidates(
        for request: LyricsSearchRequest,
        limit: Int
    ) async -> [LyricsSearchCandidate] {
        await searchHandler(request, limit)
    }
}

private final class LyricsProviderSearchAdapter: @unchecked Sendable {
    nonisolated(unsafe) private let provider: LyricsService.LyricsProvider
    private let service: String

    init(
        provider: LyricsService.LyricsProvider,
        service: String
    ) {
        self.provider = provider
        self.service = service
    }

    func searchCandidates(
        for request: LyricsSearchRequest,
        limit: Int
    ) async -> [LyricsSearchCandidate] {
        var limitedRequest = request
        limitedRequest.limit = max(1, limit)
        let fallback = Self.fallbackMetadata(for: request)
        var results: [LyricsSearchCandidate] = []

        do {
            for try await lyrics in provider.lyrics(for: limitedRequest) {
                guard Task.isCancelled == false else { break }
                guard let timedLyrics = TimedLyrics(
                    lyricsKitLyrics: lyrics,
                    service: lyrics.metadata.service ?? service,
                    fallbackTitle: fallback.title,
                    fallbackArtist: fallback.artist
                ) else {
                    continue
                }

                results.append(LyricsSearchCandidate(lyrics: timedLyrics))
                if results.count >= limitedRequest.limit {
                    break
                }
            }
        } catch {}

        return results
    }

    private static func fallbackMetadata(for request: LyricsSearchRequest) -> (title: String, artist: String) {
        switch request.searchTerm {
        case let .info(title, artist):
            return (title, artist)
        case let .keyword(keyword):
            return (keyword, "")
        }
    }
}

enum LyricsKitSearchServices {
    static func `default`() -> [any LyricsSearchServicing] {
        LyricsKitServiceConfiguration.defaultServices.map { service in
            makeSearchService(
                provider: service.create(),
                service: service.displayName
            )
        }
    }

    private static func makeSearchService(
        provider: LyricsService.LyricsProvider,
        service: String
    ) -> AnyLyricsSearchService {
        let adapter = LyricsProviderSearchAdapter(provider: provider, service: service)
        return AnyLyricsSearchService { request, limit in
            await adapter.searchCandidates(for: request, limit: limit)
        }
    }
}

enum LyricsKitServiceConfiguration {
    static let defaultServices: [LyricsProviders.Service] = [
        .qq,
        .kugou,
        .netease,
        .musixmatch,
        .lrclib,
    ]
}
