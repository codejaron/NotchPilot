import Foundation
import LyricsKit
@preconcurrency import LyricsService

struct LyricsSearchCandidate: Identifiable {
    let id: String
    let title: String
    let artist: String
    let service: String
    let quality: Double
    let duration: TimeInterval?

    private let loadLyricsHandler: @Sendable () async throws -> TimedLyrics

    init(
        id: String,
        title: String,
        artist: String,
        service: String,
        quality: Double = 0,
        duration: TimeInterval? = nil,
        loadLyrics: @escaping @Sendable () async throws -> TimedLyrics
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.service = service
        self.quality = quality
        self.duration = duration
        self.loadLyricsHandler = loadLyrics
    }

    init(lyrics: TimedLyrics, quality: Double = 0) {
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
            quality: quality,
            duration: lyrics.duration,
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
            lhs.service == rhs.service &&
            lhs.quality == rhs.quality &&
            lhs.duration == rhs.duration
    }
}

enum LyricsSearchCandidateRanker {
    static func ranked(
        _ candidates: [LyricsSearchCandidate],
        requestTitle: String,
        requestArtist: String,
        duration: TimeInterval?,
        limit: Int
    ) -> [LyricsSearchCandidate] {
        let entries = deduplicatedEntries(
            candidates,
            requestTitle: requestTitle,
            requestArtist: requestArtist,
            duration: duration
        )

        return entries
            .sorted { lhs, rhs in
                compare(
                    lhs,
                    rhs,
                    requestTitle: requestTitle,
                    requestArtist: requestArtist,
                    duration: duration
                )
            }
            .prefix(max(0, limit))
            .map(\.candidate)
    }

    private struct Entry {
        let candidate: LyricsSearchCandidate
        let firstIndex: Int
    }

    private static func deduplicatedEntries(
        _ candidates: [LyricsSearchCandidate],
        requestTitle: String,
        requestArtist: String,
        duration: TimeInterval?
    ) -> [Entry] {
        var entries: [Entry] = []
        var indexesByIdentifier: [String: Int] = [:]

        for (index, candidate) in candidates.enumerated() {
            let identifier = deduplicationIdentifier(for: candidate)
            if let existingIndex = indexesByIdentifier[identifier] {
                let existing = entries[existingIndex]
                let replacement = Entry(candidate: candidate, firstIndex: existing.firstIndex)
                if compare(
                    replacement,
                    existing,
                    requestTitle: requestTitle,
                    requestArtist: requestArtist,
                    duration: duration
                ) {
                    entries[existingIndex] = replacement
                }
                continue
            }

            indexesByIdentifier[identifier] = entries.count
            entries.append(Entry(candidate: candidate, firstIndex: index))
        }

        return entries
    }

    private static func deduplicationIdentifier(for candidate: LyricsSearchCandidate) -> String {
        [
            candidate.service,
            LyricsTrackKey.normalize(candidate.artist),
            LyricsTrackKey.normalize(candidate.title),
        ].joined(separator: "|")
    }

    private static func compare(
        _ lhs: Entry,
        _ rhs: Entry,
        requestTitle: String,
        requestArtist: String,
        duration: TimeInterval?
    ) -> Bool {
        let qualityDifference = lhs.candidate.quality - rhs.candidate.quality
        if abs(qualityDifference) > 0.0001 {
            return qualityDifference > 0
        }

        let lhsMatchScore = matchScore(
            candidate: lhs.candidate,
            requestTitle: requestTitle,
            requestArtist: requestArtist
        )
        let rhsMatchScore = matchScore(
            candidate: rhs.candidate,
            requestTitle: requestTitle,
            requestArtist: requestArtist
        )
        let matchDifference = lhsMatchScore - rhsMatchScore
        if abs(matchDifference) > 0.0001 {
            return matchDifference > 0
        }

        let lhsDurationDifference = durationDifference(lhs.candidate, requestedDuration: duration)
        let rhsDurationDifference = durationDifference(rhs.candidate, requestedDuration: duration)
        if abs(lhsDurationDifference - rhsDurationDifference) > 0.0001 {
            return lhsDurationDifference < rhsDurationDifference
        }

        return lhs.firstIndex < rhs.firstIndex
    }

    private static func matchScore(
        candidate: LyricsSearchCandidate,
        requestTitle: String,
        requestArtist: String
    ) -> Double {
        let titleScore = componentScore(candidate.title, request: requestTitle)
        let artistScore = componentScore(candidate.artist, request: requestArtist)
        return (titleScore * 0.7) + (artistScore * 0.3)
    }

    private static func componentScore(_ candidate: String, request: String) -> Double {
        let normalizedCandidate = LyricsTrackKey.normalize(candidate)
        let normalizedRequest = LyricsTrackKey.normalize(request)

        guard normalizedRequest.isEmpty == false else {
            return 0.5
        }

        guard normalizedCandidate.isEmpty == false else {
            return 0
        }

        if normalizedCandidate == normalizedRequest {
            return 1
        }

        if normalizedCandidate.contains(normalizedRequest) ||
            normalizedRequest.contains(normalizedCandidate) {
            return 0.8
        }

        let candidateTokens = Set(normalizedCandidate.split(separator: " "))
        let requestTokens = Set(normalizedRequest.split(separator: " "))
        guard requestTokens.isEmpty == false else {
            return 0
        }

        let overlap = candidateTokens.intersection(requestTokens).count
        return Double(overlap) / Double(requestTokens.count)
    }

    private static func durationDifference(
        _ candidate: LyricsSearchCandidate,
        requestedDuration: TimeInterval?
    ) -> TimeInterval {
        guard let requestedDuration, let duration = candidate.duration else {
            return .greatestFiniteMagnitude
        }

        return abs(duration - requestedDuration)
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

                results.append(LyricsSearchCandidate(lyrics: timedLyrics, quality: lyrics.quality))
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
