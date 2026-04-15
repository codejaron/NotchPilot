import Foundation
import LyricsKit
@preconcurrency import LyricsService

struct LyricsSearchCandidate: Identifiable {
    let id: String
    let title: String
    let artist: String
    let service: String

    private let loadLyricsHandler: () async throws -> TimedLyrics

    init(
        id: String,
        title: String,
        artist: String,
        service: String,
        loadLyrics: @escaping () async throws -> TimedLyrics
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.service = service
        self.loadLyricsHandler = loadLyrics
    }

    @MainActor
    func loadLyrics() async throws -> TimedLyrics {
        try await loadLyricsHandler()
    }
}

extension LyricsSearchCandidate: Equatable {
    static func == (lhs: LyricsSearchCandidate, rhs: LyricsSearchCandidate) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.artist == rhs.artist &&
            lhs.service == rhs.service
    }
}

@MainActor
protocol LyricsSearchServicing {
    func searchCandidates(
        for request: LyricsSearchRequest,
        limit: Int
    ) async -> [LyricsSearchCandidate]
}

@MainActor
private struct AnyLyricsSearchService: LyricsSearchServicing {
    private let searchHandler: (LyricsSearchRequest, Int) async -> [LyricsSearchCandidate]

    init(
        _ searchHandler: @escaping (LyricsSearchRequest, Int) async -> [LyricsSearchCandidate]
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

private struct LyricsSearchCandidateMetadata {
    let id: String
    let title: String
    let artist: String
    let service: String
}

enum LyricsSearchCandidateLoadingError: Error {
    case invalidLyrics
}

private final class LyricsSearchCandidateLoader<Provider: _LyricsProvider>: @unchecked Sendable {
    nonisolated(unsafe) private let provider: Provider
    nonisolated(unsafe) private let token: Provider.LyricsToken
    private let service: String

    init(
        provider: Provider,
        token: Provider.LyricsToken,
        service: String
    ) {
        self.provider = provider
        self.token = token
        self.service = service
    }

    func load() async throws -> TimedLyrics {
        let lyrics = try await provider.fetch(with: token)
        guard let timedLyrics = TimedLyrics(
            lyricsKitLyrics: lyrics,
            service: service
        ) else {
            throw LyricsSearchCandidateLoadingError.invalidLyrics
        }
        return timedLyrics
    }
}

@MainActor
enum LyricsKitSearchServices {
    static func `default`() -> [any LyricsSearchServicing] {
        [
            qqMusic(),
            kugou(),
            netEase(),
            musixmatch(),
            lrclib(),
        ]
    }

    private static func qqMusic() -> AnyLyricsSearchService {
        let provider = LyricsProviders.QQMusic()
        return makeSearchService(
            provider: provider,
            service: LyricsProviders.QQMusic.service,
            metadata: { token in
                let value = LyricsSearchReflection.child(named: "value", in: token) ?? token
                guard let title = LyricsSearchReflection.string(named: "name", in: value),
                      let artist = LyricsSearchReflection.joinedNames(
                        from: LyricsSearchReflection.child(named: "singer", in: value)
                      ) ?? LyricsSearchReflection.string(named: "singer", in: value),
                      let identifier = LyricsSearchReflection.string(named: "mid", in: value)
                        ?? LyricsSearchReflection.string(named: "id", in: value) else {
                    return nil
                }

                return LyricsSearchCandidateMetadata(
                    id: "qq|\(identifier)",
                    title: title,
                    artist: artist,
                    service: LyricsProviders.QQMusic.service
                )
            }
        )
    }

    private static func kugou() -> AnyLyricsSearchService {
        let provider = LyricsProviders.Kugou()
        return makeSearchService(
            provider: provider,
            service: LyricsProviders.Kugou.service,
            metadata: { token in
                let value = LyricsSearchReflection.child(named: "value", in: token) ?? token
                guard let hash = LyricsSearchReflection.string(named: "hash", in: value),
                      let albumAudioID = LyricsSearchReflection.int(named: "albumAudioID", in: value),
                      let resolved = await resolveKugouMetadata(hash: hash, albumAudioID: albumAudioID) else {
                    return nil
                }

                return LyricsSearchCandidateMetadata(
                    id: "kugou|\(hash)|\(albumAudioID)",
                    title: resolved.title,
                    artist: resolved.artist,
                    service: LyricsProviders.Kugou.service
                )
            }
        )
    }

    private static func netEase() -> AnyLyricsSearchService {
        let provider = LyricsProviders.NetEase()
        return makeSearchService(
            provider: provider,
            service: LyricsProviders.NetEase.service,
            metadata: { token in
                let value = LyricsSearchReflection.child(named: "value", in: token) ?? token
                guard let title = LyricsSearchReflection.string(named: "name", in: value),
                      let artist = LyricsSearchReflection.joinedNames(
                        from: LyricsSearchReflection.child(named: "artists", in: value)
                      ),
                      let identifier = LyricsSearchReflection.string(named: "id", in: value) else {
                    return nil
                }

                return LyricsSearchCandidateMetadata(
                    id: "netease|\(identifier)",
                    title: title,
                    artist: artist,
                    service: LyricsProviders.NetEase.service
                )
            }
        )
    }

    private static func musixmatch() -> AnyLyricsSearchService {
        let provider = LyricsProviders.Musixmatch()
        return makeSearchService(
            provider: provider,
            service: LyricsProviders.Musixmatch.service,
            metadata: { token in
                let value = LyricsSearchReflection.child(named: "value", in: token) ?? token
                guard let title = LyricsSearchReflection.string(named: "trackName", in: value),
                      let artist = LyricsSearchReflection.string(named: "artistName", in: value),
                      let identifier = LyricsSearchReflection.string(named: "trackId", in: value) else {
                    return nil
                }

                return LyricsSearchCandidateMetadata(
                    id: "musixmatch|\(identifier)",
                    title: title,
                    artist: artist,
                    service: LyricsProviders.Musixmatch.service
                )
            }
        )
    }

    private static func lrclib() -> AnyLyricsSearchService {
        let provider = LyricsProviders.LRCLIB()
        return makeSearchService(
            provider: provider,
            service: LyricsProviders.LRCLIB.service,
            metadata: { token in
                let value = LyricsSearchReflection.child(named: "value", in: token) ?? token
                guard let title = LyricsSearchReflection.string(named: "trackName", in: value),
                      let artist = LyricsSearchReflection.string(named: "artistName", in: value),
                      let identifier = LyricsSearchReflection.string(named: "id", in: value) else {
                    return nil
                }

                return LyricsSearchCandidateMetadata(
                    id: "lrclib|\(identifier)",
                    title: title,
                    artist: artist,
                    service: LyricsProviders.LRCLIB.service
                )
            }
        )
    }

    private static func makeSearchService<Provider: _LyricsProvider>(
        provider: Provider,
        service: String,
        metadata: @escaping @MainActor (Provider.LyricsToken) async -> LyricsSearchCandidateMetadata?
    ) -> AnyLyricsSearchService {
        AnyLyricsSearchService { request, limit in
            nonisolated(unsafe) let unsafeProvider = provider
            let tokens = (try? await unsafeProvider.search(for: request)) ?? []
            var results: [LyricsSearchCandidate] = []

            for token in tokens.prefix(limit) {
                nonisolated(unsafe) let unsafeToken = token

                guard let metadata = await metadata(unsafeToken) else {
                    continue
                }

                let loader = LyricsSearchCandidateLoader(
                    provider: unsafeProvider,
                    token: unsafeToken,
                    service: service
                )

                results.append(
                    LyricsSearchCandidate(
                        id: metadata.id,
                        title: metadata.title,
                        artist: metadata.artist,
                        service: metadata.service,
                        loadLyrics: {
                            try await loader.load()
                        }
                    )
                )
            }

            return results
        }
    }

    private static func resolveKugouMetadata(
        hash: String,
        albumAudioID: Int
    ) async -> (title: String, artist: String)? {
        guard let url = URL(
            string: "https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration=&hash=\(hash)&album_audio_id=\(albumAudioID)"
        ) else {
            return nil
        }

        guard let (data, _) = try? await URLSession.shared.data(for: .init(url: url)),
              let response = try? JSONDecoder().decode(KugouCandidateResponse.self, from: data),
              let first = response.candidates.first else {
            return nil
        }

        return (first.song, first.singer)
    }
}

private struct KugouCandidateResponse: Decodable {
    struct Candidate: Decodable {
        let song: String
        let singer: String
    }

    let candidates: [Candidate]
}

private enum LyricsSearchReflection {
    static func child(named name: String, in value: Any) -> Any? {
        Mirror(reflecting: unwrap(value)).children.first(where: { $0.label == name })?.value
    }

    static func string(named name: String, in value: Any) -> String? {
        string(from: child(named: name, in: value))
    }

    static func int(named name: String, in value: Any) -> Int? {
        int(from: child(named: name, in: value))
    }

    static func joinedNames(from value: Any?) -> String? {
        guard let values = array(from: value) else {
            return nil
        }

        let names = values.compactMap { item in
            string(named: "name", in: item) ?? string(from: item)
        }

        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private static func array(from value: Any?) -> [Any]? {
        guard let value else {
            return nil
        }

        let unwrapped = unwrap(value)
        if let array = unwrapped as? [Any] {
            return array
        }

        let mirror = Mirror(reflecting: unwrapped)
        guard mirror.displayStyle == .collection else {
            return nil
        }

        return mirror.children.map(\.value)
    }

    private static func string(from value: Any?) -> String? {
        guard let value else {
            return nil
        }

        let unwrapped = unwrap(value)
        switch unwrapped {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let int as Int:
            return String(int)
        case let int64 as Int64:
            return String(int64)
        case let double as Double:
            return String(double)
        default:
            return nil
        }
    }

    private static func int(from value: Any?) -> Int? {
        guard let value else {
            return nil
        }

        let unwrapped = unwrap(value)
        switch unwrapped {
        case let int as Int:
            return int
        case let int32 as Int32:
            return Int(int32)
        case let int64 as Int64:
            return Int(int64)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func unwrap(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }

        return mirror.children.first?.value ?? value
    }
}
