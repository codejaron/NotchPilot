import Foundation
import LyricsKit

struct LyricsTrackKey: Sendable {
    let title: String
    let artist: String
    let album: String
    let roundedDuration: Int?

    init(title: String, artist: String, album: String, duration: TimeInterval?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        self.title = Self.normalize(trimmedTitle)
        self.artist = Self.normalize(trimmedArtist)
        self.album = Self.normalize(album)
        self.roundedDuration = duration.map { Int($0.rounded()) }
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
        let stem = [artist, title]
            .filter { $0.isEmpty == false }
            .joined(separator: " - ")
            .sanitizedFileNameComponent

        return (stem.isEmpty ? "Lyrics" : stem) + ".json"
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
    struct InlineTag: Equatable, Codable, Sendable {
        let index: Int
        let timeOffset: TimeInterval
    }

    let timestamp: TimeInterval
    let text: String
    let translation: String?
    let inlineTags: [InlineTag]?

    init(timestamp: TimeInterval, text: String, translation: String? = nil, inlineTags: [InlineTag]? = nil) {
        self.timestamp = timestamp
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.translation = translation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        self.inlineTags = inlineTags
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

    var hasInlineTags: Bool {
        lines.contains { ($0.inlineTags?.count ?? 0) >= 2 }
    }

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

    init?(
        lyricsKitLyrics lyrics: Lyrics,
        service: String,
        fallbackTitle: String = "",
        fallbackArtist: String = ""
    ) {
        let rawTitle = lyrics.idTags[.title]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawArtist = lyrics.idTags[.artist]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty
            ? fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            : rawTitle
        let artist = rawArtist.isEmpty
            ? fallbackArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            : rawArtist

        guard title.isEmpty == false, artist.isEmpty == false else {
            return nil
        }

        self.init(
            title: title,
            artist: artist,
            album: lyrics.idTags[.album]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            duration: lyrics.length,
            service: service,
            lines: lyrics.lines.map { line in
                let inlineTags: [TimedLyricLine.InlineTag]? = line.attachments.timetag.map { timetag in
                    timetag.tags.map { tag in
                        TimedLyricLine.InlineTag(index: tag.index, timeOffset: tag.time)
                    }
                }
                return TimedLyricLine(
                    timestamp: line.position,
                    text: line.content,
                    translation: line.attachments.translation(),
                    inlineTags: inlineTags
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
        let lineTimeOffset: TimeInterval
        let lineDuration: TimeInterval
    }

    func linePair(at time: TimeInterval) -> LinePair? {
        guard lines.isEmpty == false else {
            return nil
        }

        let currentIndex = lines.lastIndex(where: { $0.timestamp <= time }) ?? 0
        let currentLine = lines[currentIndex]
        let nextLine = lines[(currentIndex + 1)...].first

        let lineTimeOffset = max(0, time - currentLine.timestamp)
        let lineDuration: TimeInterval
        if let nextLine {
            lineDuration = nextLine.timestamp - currentLine.timestamp
        } else if let trackDuration = duration {
            lineDuration = max(0, trackDuration - currentLine.timestamp)
        } else {
            lineDuration = 10.0
        }

        return LinePair(
            current: currentLine,
            next: nextLine,
            lineTimeOffset: lineTimeOffset,
            lineDuration: lineDuration
        )
    }
}

struct DesktopLyricsLineState: Equatable, Sendable {
    let currentLine: String
    let nextLine: String?
    let inlineTags: [TimedLyricLine.InlineTag]?
    let lineStartDate: Date
    let lineDuration: TimeInterval
}

struct DesktopLyricsPresentation: Equatable, Sendable {
    let isVisible: Bool
    let lineState: DesktopLyricsLineState?

    var currentLine: String? { lineState?.currentLine }
    var nextLine: String? { lineState?.nextLine }

    func karaokeFraction(at date: Date = Date()) -> Double {
        guard let lineState else {
            return 1.0
        }
        let timeOffset = max(0, date.timeIntervalSince(lineState.lineStartDate))
        return DesktopLyricsKaraokeMath.fraction(
            inlineTags: lineState.inlineTags,
            lineTimeOffset: timeOffset,
            lineDuration: lineState.lineDuration,
            characterCount: lineState.currentLine.count
        )
    }

    static let hidden = DesktopLyricsPresentation(isVisible: false, lineState: nil)
}

enum DesktopLyricsPresentationResolver {
    static func resolve(
        playbackState: MediaPlaybackState,
        lyrics: TimedLyrics?,
        offsetMilliseconds: Int = 0,
        at date: Date = Date()
    ) -> DesktopLyricsPresentation {
        guard case let .active(snapshot) = playbackState,
              snapshot.isPlaying,
              let lyrics else {
            return .hidden
        }

        let offset = TimeInterval(offsetMilliseconds) / 1000.0
        let adjustedTime = snapshot.estimatedCurrentTime(at: date) + offset
        guard let pair = lyrics.linePair(at: adjustedTime) else {
            return .hidden
        }

        let lineStartDate = date.addingTimeInterval(-pair.lineTimeOffset)
        let lineState = DesktopLyricsLineState(
            currentLine: pair.current.text,
            nextLine: pair.current.translation ?? pair.next?.text,
            inlineTags: pair.current.inlineTags,
            lineStartDate: lineStartDate,
            lineDuration: pair.lineDuration
        )

        return DesktopLyricsPresentation(isVisible: true, lineState: lineState)
    }
}

enum DesktopLyricsKaraokeMath {
    static func fraction(
        inlineTags: [TimedLyricLine.InlineTag]?,
        lineTimeOffset: TimeInterval,
        lineDuration: TimeInterval,
        characterCount: Int
    ) -> Double {
        guard characterCount > 0 else { return 1.0 }

        if let tags = inlineTags, tags.count >= 2 {
            return interpolateCharacterProgress(
                tags: tags,
                timeOffset: lineTimeOffset,
                totalCharacters: characterCount
            )
        }

        guard lineDuration > 0 else { return 1.0 }
        let charBasedDuration = Double(characterCount) * 0.3
        let effectiveDuration = max(1.0, min(charBasedDuration, lineDuration))
        return min(1.0, max(0.0, lineTimeOffset / effectiveDuration))
    }

    private static func interpolateCharacterProgress(
        tags: [TimedLyricLine.InlineTag],
        timeOffset: TimeInterval,
        totalCharacters: Int
    ) -> Double {
        guard totalCharacters > 0, let first = tags.first, let last = tags.last else { return 1.0 }

        if timeOffset <= first.timeOffset {
            return Double(first.index) / Double(totalCharacters)
        }

        if timeOffset >= last.timeOffset {
            let lastFraction = Double(last.index) / Double(totalCharacters)
            let remainingChars = totalCharacters - last.index
            guard remainingChars > 0 else { return 1.0 }

            let avgDuration: TimeInterval
            if last.index > first.index, last.timeOffset > first.timeOffset {
                avgDuration = (last.timeOffset - first.timeOffset) / Double(last.index - first.index)
            } else {
                avgDuration = 0.15
            }

            let remainingDuration = avgDuration * Double(remainingChars)
            let elapsed = timeOffset - last.timeOffset
            let progress = min(1.0, elapsed / max(0.001, remainingDuration))
            return lastFraction + (1.0 - lastFraction) * progress
        }

        for i in 0 ..< (tags.count - 1) {
            let current = tags[i]
            let next = tags[i + 1]
            if timeOffset >= current.timeOffset && timeOffset < next.timeOffset {
                let timeFraction = (timeOffset - current.timeOffset) / (next.timeOffset - current.timeOffset)
                let charProgress = Double(current.index) + timeFraction * Double(next.index - current.index)
                return min(1.0, max(0.0, charProgress / Double(totalCharacters)))
            }
        }

        return 1.0
    }
}
