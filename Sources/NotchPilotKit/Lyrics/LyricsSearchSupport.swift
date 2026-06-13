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
    let hasInlineTags: Bool

    private let loadLyricsHandler: @Sendable () async throws -> TimedLyrics

    init(
        id: String,
        title: String,
        artist: String,
        service: String,
        quality: Double = 0,
        duration: TimeInterval? = nil,
        hasInlineTags: Bool = false,
        loadLyrics: @escaping @Sendable () async throws -> TimedLyrics
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.service = service
        self.quality = quality
        self.duration = duration
        self.hasInlineTags = hasInlineTags
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
            hasInlineTags: lyrics.hasInlineTags,
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
            lhs.duration == rhs.duration &&
            lhs.hasInlineTags == rhs.hasInlineTags
    }
}

struct LyricsCandidatePreference {
    let score: Double
    let metadataScore: Double
    let durationDifference: TimeInterval
    let sourceRank: Int
    let hasInlineTags: Bool

    private static let artistWeight = 0.45
    private static let titleWeight = 0.40
    private static let durationWeight = 0.15
    private static let inlineTimeTagBonus = 0.05
    private static let alternateVersionPenalty = 0.30
    private static let alternateVersionKeywords = [
        "伴奏", "无人声", "纯音乐", "卡拉ok", "伴唱",
        "instrumental", "inst.", "karaoke",
        "off vocal", "off-vocal", "offvocal",
        "acapella", "a capella",
    ]
    private static let sourceTieBreakOrder = [
        "kugou",
        "qqmusic",
        "netease",
        "musixmatch",
        "lrclib",
    ]

    static func make(
        candidate: LyricsSearchCandidate,
        requestTitle: String,
        requestArtist: String,
        duration: TimeInterval?
    ) -> LyricsCandidatePreference {
        make(
            title: candidate.title,
            artist: candidate.artist,
            service: candidate.service,
            baseQuality: candidate.quality,
            candidateDuration: candidate.duration,
            hasInlineTags: candidate.hasInlineTags,
            requestTitle: requestTitle,
            requestArtist: requestArtist,
            duration: duration
        )
    }

    static func make(
        lyrics: TimedLyrics,
        baseQuality: Double,
        requestTitle: String,
        requestArtist: String,
        duration: TimeInterval?
    ) -> LyricsCandidatePreference {
        make(
            title: lyrics.title,
            artist: lyrics.artist,
            service: lyrics.service,
            baseQuality: baseQuality,
            candidateDuration: lyrics.duration,
            hasInlineTags: lyrics.hasInlineTags,
            requestTitle: requestTitle,
            requestArtist: requestArtist,
            duration: duration
        )
    }

    static func make(
        title: String,
        artist: String,
        service: String,
        baseQuality: Double,
        candidateDuration: TimeInterval?,
        hasInlineTags: Bool,
        requestTitle: String,
        requestArtist: String,
        duration: TimeInterval?
    ) -> LyricsCandidatePreference {
        let titleScore = componentScore(title, request: requestTitle)
        let artistScore = componentScore(artist, request: requestArtist)
        let metadataScore = ((titleScore * titleWeight) + (artistScore * artistWeight)) / (titleWeight + artistWeight)
        let durationPreference = durationPreference(candidateDuration, requestedDuration: duration)
        let sourceRank = rank(for: service)
        let penalty = unwantedVersionPenalty(title: title, requestTitle: requestTitle)
        let computedQuality = (artistScore * artistWeight)
            + (titleScore * titleWeight)
            + (durationPreference.score * durationWeight)
        let suppliedQuality = baseQuality > 0 ? max(0, min(baseQuality, 1)) : computedQuality
        let timingBonus = hasInlineTags ? inlineTimeTagBonus : 0
        let score = max(0, min(1, computedQuality + ((suppliedQuality - computedQuality) * 0.25) + timingBonus - penalty))

        return LyricsCandidatePreference(
            score: score,
            metadataScore: metadataScore,
            durationDifference: durationPreference.difference,
            sourceRank: sourceRank,
            hasInlineTags: hasInlineTags
        )
    }

    static func prefers(
        _ existing: LyricsCandidatePreference,
        over candidate: LyricsCandidatePreference
    ) -> Bool {
        if abs(existing.score - candidate.score) > 0.0001 {
            return existing.score > candidate.score
        }

        if abs(existing.metadataScore - candidate.metadataScore) > 0.0001 {
            return existing.metadataScore > candidate.metadataScore
        }

        if existing.hasInlineTags != candidate.hasInlineTags {
            return existing.hasInlineTags
        }

        if abs(existing.durationDifference - candidate.durationDifference) > 0.0001 {
            return existing.durationDifference < candidate.durationDifference
        }

        return existing.sourceRank <= candidate.sourceRank
    }

    private static func componentScore(_ candidate: String, request: String) -> Double {
        let normalizedCandidate = comparableText(candidate)
        let normalizedRequest = comparableText(request)

        guard normalizedRequest.isEmpty == false else {
            return 0.6
        }

        guard normalizedCandidate.isEmpty == false else {
            return 0.3
        }

        if normalizedCandidate == normalizedRequest {
            return 1
        }

        let candidateTokens = normalizedCandidate.split(separator: " ").map(String.init)
        let requestTokens = normalizedRequest.split(separator: " ").map(String.init)
        let overlap = Set(candidateTokens).intersection(Set(requestTokens)).count
        if overlap > 0 {
            let precision = Double(overlap) / Double(max(candidateTokens.count, 1))
            let recall = Double(overlap) / Double(max(requestTokens.count, 1))
            let harmonic = (2 * precision * recall) / max(precision + recall, 0.0001)
            return max(harmonic, characterSimilarity(normalizedCandidate, normalizedRequest) * 0.9)
        }

        if normalizedCandidate.contains(normalizedRequest) || normalizedRequest.contains(normalizedCandidate) {
            return 0.72
        }

        return characterSimilarity(normalizedCandidate, normalizedRequest)
    }

    private static func comparableText(_ value: String) -> String {
        let mutable = NSMutableString(string: value)
        _ = CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return LyricsTrackKey.normalize(mutable as String)
    }

    private static func durationPreference(
        _ candidateDuration: TimeInterval?,
        requestedDuration: TimeInterval?
    ) -> (score: Double, difference: TimeInterval) {
        guard let requestedDuration, requestedDuration > 0 else {
            return (0.6, .greatestFiniteMagnitude)
        }

        guard let candidateDuration, candidateDuration > 0 else {
            return (0.55, .greatestFiniteMagnitude)
        }

        let difference = abs(candidateDuration - requestedDuration)
        guard difference < 10 else {
            return (0.5, difference)
        }
        return (1 - pow(difference / 10, 2) * 0.5, difference)
    }

    private static func unwantedVersionPenalty(title: String, requestTitle: String) -> Double {
        let normalizedTitle = title.lowercased()
        guard alternateVersionKeywords.contains(where: { normalizedTitle.contains($0) }) else {
            return 0
        }

        let normalizedRequest = requestTitle.lowercased()
        return alternateVersionKeywords.contains(where: { normalizedRequest.contains($0) })
            ? 0
            : alternateVersionPenalty
    }

    private static func rank(for service: String) -> Int {
        let normalized = service.lowercased()
        return sourceTieBreakOrder.firstIndex(of: normalized) ?? sourceTieBreakOrder.count
    }

    private static func characterSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        guard left.isEmpty == false, right.isEmpty == false else {
            return 0
        }

        var previous = Array(0 ... right.count)
        var current = previous

        for leftIndex in 1 ... left.count {
            current[0] = leftIndex
            for rightIndex in 1 ... right.count {
                if left[leftIndex - 1] == right[rightIndex - 1] {
                    current[rightIndex] = previous[rightIndex - 1]
                } else {
                    current[rightIndex] = min(
                        previous[rightIndex - 1],
                        previous[rightIndex],
                        current[rightIndex - 1]
                    ) + 1
                }
            }
            previous = current
        }

        let distance = previous[right.count]
        let length = max(left.count, right.count)
        return max(0, 1 - (Double(distance) / Double(length)))
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
        let preference: LyricsCandidatePreference
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
            let preference = LyricsCandidatePreference.make(
                candidate: candidate,
                requestTitle: requestTitle,
                requestArtist: requestArtist,
                duration: duration
            )

            if let existingIndex = indexesByIdentifier[identifier] {
                let existing = entries[existingIndex]
                let replacement = Entry(candidate: candidate, firstIndex: existing.firstIndex, preference: preference)
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
            entries.append(Entry(candidate: candidate, firstIndex: index, preference: preference))
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
        let scoreDifference = lhs.preference.score - rhs.preference.score
        if abs(scoreDifference) > 0.0001 {
            return scoreDifference > 0
        }

        let metadataDifference = lhs.preference.metadataScore - rhs.preference.metadataScore
        if abs(metadataDifference) > 0.0001 {
            return metadataDifference > 0
        }

        let qualityDifference = lhs.candidate.quality - rhs.candidate.quality
        if abs(qualityDifference) > 0.0001 {
            return qualityDifference > 0
        }

        let lhsDurationDifference = lhs.preference.durationDifference
        let rhsDurationDifference = rhs.preference.durationDifference
        if abs(lhsDurationDifference - rhsDurationDifference) > 0.0001 {
            return lhsDurationDifference < rhsDurationDifference
        }

        if lhs.preference.sourceRank != rhs.preference.sourceRank {
            return lhs.preference.sourceRank < rhs.preference.sourceRank
        }

        return lhs.firstIndex < rhs.firstIndex
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
                let metadata = Self.metadata(for: lyrics)
                guard let timedLyrics = TimedLyrics(
                    lyricsKitLyrics: lyrics,
                    service: lyrics.metadata.service ?? service,
                    fallbackTitle: fallback.title,
                    fallbackArtist: fallback.artist
                ) else {
                    continue
                }

                results.append(
                    LyricsSearchCandidate(
                        id: [
                            timedLyrics.service,
                            LyricsTrackKey.normalize(metadata.artist),
                            LyricsTrackKey.normalize(metadata.title),
                            timedLyrics.duration.map { String(Int($0.rounded())) } ?? "",
                        ].joined(separator: "|"),
                        title: metadata.title,
                        artist: metadata.artist,
                        service: timedLyrics.service,
                        quality: lyrics.quality,
                        duration: timedLyrics.duration,
                        hasInlineTags: timedLyrics.hasInlineTags,
                        loadLyrics: { timedLyrics }
                    )
                )
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

    private static func metadata(for lyrics: Lyrics) -> (title: String, artist: String) {
        (
            lyrics.idTags[.title]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            lyrics.idTags[.artist]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}

enum LyricsKitSearchServices {
    static func `default`(allowInsecureHTTP: Bool = false) -> [any LyricsSearchServicing] {
        LyricsKitServiceConfiguration.services(allowInsecureHTTP: allowInsecureHTTP).map { service in
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
    private static let allDefaultServices: [LyricsProviders.Service] = [
        .qq,
        .kugou,
        .netease,
        .musixmatch,
        .lrclib,
    ]

    private static let knownHTTPServices: Set<LyricsProviders.Service> = [
        .kugou,
        .netease,
    ]

    static let defaultServices: [LyricsProviders.Service] = services(allowInsecureHTTP: false)

    static func services(allowInsecureHTTP: Bool) -> [LyricsProviders.Service] {
        guard allowInsecureHTTP == false else {
            return allDefaultServices
        }

        return allDefaultServices.filter { knownHTTPServices.contains($0) == false }
    }
}
