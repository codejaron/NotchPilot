import Foundation
import LyricsKit

struct LyricsTrackKey: Sendable {
    let title: String
    let artist: String
    let album: String
    let roundedDuration: Int?
    private let displayTitle: String
    private let displayArtist: String

    init(title: String, artist: String, album: String, duration: TimeInterval?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        self.title = Self.normalize(trimmedTitle)
        self.artist = Self.normalize(trimmedArtist)
        self.album = Self.normalize(album)
        self.roundedDuration = duration.map { Int($0.rounded()) }
        self.displayTitle = trimmedTitle
        self.displayArtist = trimmedArtist
    }

    init(snapshot: MediaPlaybackSnapshot) {
        self.init(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration
        )
    }

    var cacheFileName: String {
        let readableStem = [displayArtist, displayTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " - ")
            .sanitizedFileNameComponent

        return (readableStem.isEmpty ? storageIdentifier.replacingOccurrences(of: "|", with: " - ") : readableStem)
            + ".json"
    }

    var storageIdentifier: String {
        "\(artist)|\(title)"
    }

    var hasPrimaryMetadata: Bool {
        title.isEmpty == false && artist.isEmpty == false
    }

    static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    static func normalizeBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func bundleIdentifierHasAnyPrefix(
        _ bundleIdentifier: String?,
        prefixes: some Sequence<String>
    ) -> Bool {
        guard let bundleIdentifier = normalizeBundleIdentifier(bundleIdentifier) else {
            return false
        }

        return prefixes.contains(where: { bundleIdentifier.hasPrefix($0) })
    }
}

extension LyricsTrackKey: Equatable {
    static func == (lhs: LyricsTrackKey, rhs: LyricsTrackKey) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist
    }
}

extension LyricsTrackKey: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(artist)
    }
}

struct TimedLyricLine: Equatable, Codable, Sendable {
    let timestamp: TimeInterval
    let text: String
    let translation: String?

    init(timestamp: TimeInterval, text: String, translation: String? = nil) {
        self.timestamp = timestamp
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.translation = translation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var sanitizedFileNameComponent: String {
        let invalidCharacterSet = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let collapsed = components(separatedBy: invalidCharacterSet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")

        return collapsed.isEmpty ? "Lyrics" : collapsed
    }
}

enum DesktopLyricsPlaybackFilter {
    private static let allowedBundlePrefixes: [String] = [
        "com.spotify.client",
        "com.apple.music",
        "com.apple.itunes",
        "com.tencent.qqmusic",
        "com.netease.163music",
        "com.netease.cloudmusic",
        "com.kugou.music",
        "com.kugou.client",
        "com.deezer",
        "com.tidal",
        "com.amazon.music",
        "sh.cider",
    ]

    private static let allowedBundleKeywords: [String] = [
        "spotify",
        "music",
        "qqmusic",
        "netease",
        "cloudmusic",
        "kugou",
        "tidal",
        "deezer",
        "cider",
    ]

    static func isEligible(_ snapshot: MediaPlaybackSnapshot) -> Bool {
        let trackKey = LyricsTrackKey(snapshot: snapshot)
        guard trackKey.hasPrimaryMetadata,
              let bundleIdentifier = LyricsTrackKey.normalizeBundleIdentifier(snapshot.source.bundleIdentifier) else {
            return false
        }

        if LyricsTrackKey.bundleIdentifierHasAnyPrefix(bundleIdentifier, prefixes: allowedBundlePrefixes) {
            return true
        }

        return allowedBundleKeywords.contains(where: { bundleIdentifier.contains($0) })
    }
}

struct TimedLyrics: Equatable, Codable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval?
    let service: String
    let lines: [TimedLyricLine]

    init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?,
        service: String,
        lines: [TimedLyricLine]
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.service = service
        self.lines = lines
            .filter { $0.text.isEmpty == false }
            .sorted { $0.timestamp < $1.timestamp }
    }

    init?(lyricsKitLyrics lyrics: Lyrics, service: String) {
        let title = lyrics.idTags[.title]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = lyrics.idTags[.artist]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard title.isEmpty == false, artist.isEmpty == false else {
            return nil
        }

        self.init(
            title: title,
            artist: artist,
            album: lyrics.idTags[.album]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            duration: lyrics.length,
            service: service,
            lines: lyrics.lines.map {
                TimedLyricLine(
                    timestamp: $0.position,
                    text: $0.content,
                    translation: $0.attachments.translation()
                )
            }
        )

        guard lines.isEmpty == false else {
            return nil
        }
    }

    struct LinePair: Equatable, Sendable {
        let current: TimedLyricLine
        let next: TimedLyricLine?
    }

    func linePair(at time: TimeInterval) -> LinePair? {
        guard lines.isEmpty == false else {
            return nil
        }

        let currentIndex = lines.lastIndex(where: { $0.timestamp <= time }) ?? 0
        let currentLine = lines[currentIndex]
        let nextLine = lines[(currentIndex + 1)...].first
        return LinePair(current: currentLine, next: nextLine)
    }
}

struct DesktopLyricsPresentation: Equatable, Sendable {
    let isVisible: Bool
    let currentLine: String?
    let nextLine: String?

    static let hidden = DesktopLyricsPresentation(
        isVisible: false,
        currentLine: nil,
        nextLine: nil
    )
}

enum DesktopLyricsPresentationResolver {
    static func resolve(
        playbackState: MediaPlaybackState,
        lyrics: TimedLyrics?,
        at date: Date = Date()
    ) -> DesktopLyricsPresentation {
        guard case let .active(snapshot) = playbackState,
              snapshot.isPlaying,
              let lyrics,
              let pair = lyrics.linePair(at: snapshot.estimatedCurrentTime(at: date)) else {
            return .hidden
        }

        return DesktopLyricsPresentation(
            isVisible: true,
            currentLine: pair.current.text,
            nextLine: pair.current.translation ?? pair.next?.text
        )
    }
}
