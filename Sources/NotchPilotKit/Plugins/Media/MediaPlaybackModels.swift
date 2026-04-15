import Foundation

public struct MediaPlaybackSource: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let displayName: String
    public let systemImageName: String

    public init(bundleIdentifier: String?, displayName: String, systemImageName: String = "music.note") {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.systemImageName = systemImageName
    }

    public static func fromBundleIdentifier(_ bundleIdentifier: String?) -> MediaPlaybackSource {
        switch bundleIdentifier {
        case "com.spotify.client":
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "Spotify")
        case "com.apple.Music":
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "Apple Music")
        case "com.apple.iTunes":
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "iTunes")
        case "com.tencent.qqmusic":
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "QQ Music")
        case "com.netease.163music", "com.netease.cloudmusic":
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "NetEase Music")
        case "com.kugou.music", "com.kugou.client":
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "Kugou")
        case let bundleIdentifier? where bundleIdentifier.lowercased().contains("tidal"):
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "TIDAL")
        case let bundleIdentifier? where bundleIdentifier.lowercased().contains("deezer"):
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "Deezer")
        case let bundleIdentifier? where bundleIdentifier.lowercased().contains("cider"):
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: "Cider")
        case let bundleIdentifier? where bundleIdentifier.isEmpty == false:
            let fallbackName = bundleIdentifier
                .split(separator: ".")
                .last
                .map(String.init)?
                .replacingOccurrences(of: "-", with: " ")
                .capitalized ?? "Media"
            return MediaPlaybackSource(bundleIdentifier: bundleIdentifier, displayName: fallbackName)
        default:
            return MediaPlaybackSource(bundleIdentifier: nil, displayName: "Media")
        }
    }
}

public struct MediaPlaybackSnapshot: Equatable, Sendable {
    public let source: MediaPlaybackSource
    public let title: String
    public let artist: String
    public let album: String
    public let artworkData: Data?
    public let currentTime: TimeInterval
    public let duration: TimeInterval?
    public let playbackRate: Double
    public let isPlaying: Bool
    public let lastUpdated: Date

    public init(
        source: MediaPlaybackSource,
        title: String,
        artist: String,
        album: String,
        artworkData: Data?,
        currentTime: TimeInterval,
        duration: TimeInterval?,
        playbackRate: Double,
        isPlaying: Bool,
        lastUpdated: Date
    ) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.currentTime = currentTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.lastUpdated = lastUpdated
    }

    public var hasPrimaryMetadata: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public func estimatedCurrentTime(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else {
            return clampedTime(currentTime)
        }

        let elapsedSinceUpdate = max(0, date.timeIntervalSince(lastUpdated))
        let projectedTime = currentTime + (elapsedSinceUpdate * playbackRate)
        return clampedTime(projectedTime)
    }

    private func clampedTime(_ value: TimeInterval) -> TimeInterval {
        let upperBound = duration ?? value
        return min(max(0, value), max(0, upperBound))
    }
}

public enum MediaPlaybackState: Equatable, Sendable {
    case unavailable
    case idle
    case active(MediaPlaybackSnapshot)
}

struct NowPlayingSessionPayload: Equatable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let artworkData: Data?
    let timestamp: Date?
    let playbackRate: Double?
    let isPlaying: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?

    var normalizedState: MediaPlaybackState {
        let resolvedBundleIdentifier = resolvedBundleID
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedAlbum = album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard
            normalizedTitle.isEmpty == false
                || normalizedArtist.isEmpty == false
                || normalizedAlbum.isEmpty == false
                || (resolvedBundleIdentifier?.isEmpty == false)
        else {
            return .idle
        }

        return .active(
            MediaPlaybackSnapshot(
                source: .fromBundleIdentifier(resolvedBundleIdentifier),
                title: normalizedTitle,
                artist: normalizedArtist,
                album: normalizedAlbum,
                artworkData: artworkData,
                currentTime: elapsedTime ?? 0,
                duration: duration,
                playbackRate: playbackRate ?? 1,
                isPlaying: isPlaying ?? false,
                lastUpdated: timestamp ?? Date()
            )
        )
    }

    private var resolvedBundleID: String? {
        let parentBundle = parentApplicationBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parentBundle, parentBundle.isEmpty == false {
            return parentBundle
        }

        let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil
    }
}
