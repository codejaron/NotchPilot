import AppKit
import Foundation

protocol SpotifyPlaybackSnapshotProviding {
    @MainActor
    func currentSpotifyPlaybackSnapshot(at date: Date) async -> MediaPlaybackSnapshot?
}

protocol SpotifyPlaybackPlayerOperating: SpotifyPlaybackSnapshotProviding, MediaPlaybackCommandPerforming {
    func currentPlaybackTime() -> TimeInterval?
}

final class AppleScriptSpotifyPlaybackPlayer: SpotifyPlaybackPlayerOperating {
    typealias SnapshotScriptRunner = (String) -> String?
    typealias CommandScriptRunner = (String) -> Bool
    typealias PlaybackTimeScriptRunner = (String) -> TimeInterval?
    typealias ArtworkDataLoader = (URL) async -> Data?
    typealias RunningCheck = () -> Bool

    private let snapshotScriptRunner: SnapshotScriptRunner
    private let commandScriptRunner: CommandScriptRunner
    private let playbackTimeScriptRunner: PlaybackTimeScriptRunner
    private let artworkDataLoader: ArtworkDataLoader
    private let isSpotifyRunning: RunningCheck

    init(
        snapshotScriptRunner: @escaping SnapshotScriptRunner = AppleScriptSpotifyPlaybackPlayer.runSnapshotAppleScript,
        commandScriptRunner: @escaping CommandScriptRunner = AppleScriptSpotifyPlaybackPlayer.runCommandAppleScript,
        playbackTimeScriptRunner: @escaping PlaybackTimeScriptRunner = AppleScriptSpotifyPlaybackPlayer.runPlaybackTimeAppleScript,
        artworkDataLoader: @escaping ArtworkDataLoader = AppleScriptSpotifyPlaybackPlayer.loadArtworkData,
        isSpotifyRunning: @escaping RunningCheck = AppleScriptSpotifyPlaybackPlayer.isSpotifyRunning
    ) {
        self.snapshotScriptRunner = snapshotScriptRunner
        self.commandScriptRunner = commandScriptRunner
        self.playbackTimeScriptRunner = playbackTimeScriptRunner
        self.artworkDataLoader = artworkDataLoader
        self.isSpotifyRunning = isSpotifyRunning
    }

    func currentSpotifyPlaybackSnapshot(at date: Date = Date()) async -> MediaPlaybackSnapshot? {
        guard isSpotifyRunning() else {
            return nil
        }

        guard let result = snapshotScriptRunner(Self.snapshotScript) else {
            return nil
        }

        return await SpotifyPlaybackScriptResult.snapshot(
            from: result,
            artworkDataLoader: artworkDataLoader,
            at: date
        )
    }

    func currentPlaybackTime() -> TimeInterval? {
        guard isSpotifyRunning(),
              let playbackTime = playbackTimeScriptRunner(Self.playbackTimeScript),
              playbackTime >= 0 else {
            return nil
        }

        return playbackTime
    }

    func perform(_ command: MediaPlaybackCommand) -> Bool {
        guard isSpotifyRunning() else {
            return false
        }

        return commandScriptRunner(Self.commandScript(for: command))
    }

    private static let snapshotScript = """
    set sep to ASCII character 31
    tell application "Spotify"
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set trackArtworkURL to artwork url of current track
        set trackDuration to duration of current track
        set trackPosition to player position
        set trackState to player state as string
        return trackState & sep & trackPosition & sep & trackDuration & sep & trackName & sep & trackArtist & sep & trackAlbum & sep & trackArtworkURL
    end tell
    """

    private static let playbackTimeScript = "tell application \"Spotify\" to return player position"

    private static func commandScript(for command: MediaPlaybackCommand) -> String {
        switch command {
        case .play:
            return "tell application \"Spotify\" to play"
        case .pause:
            return "tell application \"Spotify\" to pause"
        case .togglePlayPause:
            return "tell application \"Spotify\" to playpause"
        case .nextTrack:
            return "tell application \"Spotify\" to next track"
        case .previousTrack:
            return "tell application \"Spotify\" to previous track"
        case let .seek(time):
            let position = time.isFinite ? max(0, time) : 0
            return "tell application \"Spotify\" to set player position to \(position)"
        }
    }

    private static func isSpotifyRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty == false
    }

    fileprivate static func loadArtworkData(from url: URL) async -> Data? {
        switch url.scheme?.lowercased() {
        case "http", "https":
            guard let (data, response) = try? await URLSession.shared.data(from: url) else {
                return nil
            }

            if let response = response as? HTTPURLResponse,
               (200..<300).contains(response.statusCode) == false {
                return nil
            }

            return data
        case "file":
            return await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value
        default:
            return nil
        }
    }

    private static func runSnapshotAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else {
            return nil
        }

        return result.stringValue
    }

    private static func runCommandAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }

    private static func runPlaybackTimeAppleScript(_ source: String) -> TimeInterval? {
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else {
            return nil
        }

        return result.doubleValue
    }
}

enum SpotifyPlaybackNotice {
    struct Payload: Sendable {
        let playback: SpotifyPlaybackValue
        let title: String?
        let artist: String?
        let album: String?
        let position: TimeInterval?
        let duration: TimeInterval?
        let artworkURL: String?
        let trackID: String?
    }

    static let name = Notification.Name("com.spotify.client.PlaybackStateChanged")

    static func payload(from userInfo: [AnyHashable: Any]) -> Payload? {
        guard let playback = SpotifyPlaybackValue(rawValue: stringValue(for: "Player State", in: userInfo)) else {
            return nil
        }

        return Payload(
            playback: playback,
            title: firstStringValue(for: ["Name", "Title", "Track Name"], in: userInfo),
            artist: firstStringValue(for: ["Artist"], in: userInfo),
            album: firstStringValue(for: ["Album"], in: userInfo),
            position: numberValue(for: "Playback Position", in: userInfo),
            duration: numberValue(for: "Duration", in: userInfo),
            artworkURL: firstStringValue(
                for: ["Artwork URL", "ArtworkURL", "Artwork Url", "Image URL", "ImageURL"],
                in: userInfo
            ),
            trackID: firstStringValue(for: ["Track ID", "TrackID", "Persistent ID"], in: userInfo)
        )
    }

    @MainActor
    static func state(
        from userInfo: [AnyHashable: Any],
        fallback: MediaPlaybackSnapshot?,
        artworkDataLoader: (URL) async -> Data? = AppleScriptSpotifyPlaybackPlayer.loadArtworkData,
        at date: Date = Date()
    ) async -> MediaPlaybackState? {
        guard let payload = payload(from: userInfo) else {
            return nil
        }

        return await state(
            from: payload,
            fallback: fallback,
            artworkDataLoader: artworkDataLoader,
            at: date
        )
    }

    @MainActor
    static func state(
        from payload: Payload,
        fallback: MediaPlaybackSnapshot?,
        artworkDataLoader: (URL) async -> Data? = AppleScriptSpotifyPlaybackPlayer.loadArtworkData,
        at date: Date = Date()
    ) async -> MediaPlaybackState? {
        guard payload.playback != .stopped else {
            return .idle
        }

        let title = payload.title ?? fallback?.title ?? ""
        let artist = payload.artist ?? fallback?.artist ?? ""
        let album = payload.album ?? fallback?.album ?? ""

        guard [title, artist, album].contains(where: { $0.isEmpty == false }) else {
            return nil
        }

        let position = payload.position
            ?? fallback.map { $0.estimatedCurrentTime(at: date) }
            ?? 0
        let duration = normalizedDuration(
            payload.duration ?? fallback?.duration
        )
        let fallbackArtwork = fallbackMatches(
            fallback,
            title: title,
            artist: artist,
            album: album
        ) ? fallback?.artworkData : nil
        let artworkData = await SpotifyArtworkData.data(
            from: payload.artworkURL,
            loader: artworkDataLoader
        ) ?? fallbackArtwork

        return .active(
            MediaPlaybackSnapshot(
                source: .fromBundleIdentifier("com.spotify.client"),
                title: title,
                artist: artist,
                album: album,
                artworkData: artworkData,
                currentTime: max(0, position),
                duration: duration,
                playbackRate: payload.playback.isPlaying ? 1 : 0,
                isPlaying: payload.playback.isPlaying,
                lastUpdated: date
            )
        )
    }

    fileprivate static func firstStringValue(
        for keys: [String],
        in userInfo: [AnyHashable: Any]
    ) -> String? {
        keys.lazy.compactMap { stringValue(for: $0, in: userInfo) }.first
    }

    fileprivate static func stringValue(
        for key: String,
        in userInfo: [AnyHashable: Any]
    ) -> String? {
        guard let value = userInfo[key] else {
            return nil
        }

        let string: String?
        if let value = value as? String {
            string = value
        } else if let value = value as? NSNumber {
            string = value.stringValue
        } else {
            string = nil
        }

        return string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForSpotifyPlayback
    }

    fileprivate static func numberValue(
        for key: String,
        in userInfo: [AnyHashable: Any]
    ) -> TimeInterval? {
        guard let value = userInfo[key] else {
            return nil
        }

        if let value = value as? NSNumber {
            return value.doubleValue
        }

        if let value = value as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let value = value as? Double {
            return value
        }

        if let value = value as? Int {
            return Double(value)
        }

        return nil
    }

    fileprivate static func normalizedDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }

        return value > 10_000 ? value / 1000 : value
    }

    private static func fallbackMatches(
        _ fallback: MediaPlaybackSnapshot?,
        title: String,
        artist: String,
        album: String
    ) -> Bool {
        fallback?.title == title
            && fallback?.artist == artist
            && fallback?.album == album
    }
}

enum SpotifyArtworkData {
    @MainActor
    static func data(from urlString: String?, loader: (URL) async -> Data?) async -> Data? {
        guard let urlString = urlString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForSpotifyPlayback,
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            ["http", "https", "file"].contains(scheme) else {
            return nil
        }

        return await loader(url)
    }
}

struct SpotifyPlaybackTrackGate {
    private var acceptedTrackID: String?

    mutating func shouldRefreshCompleteSnapshot(for trackID: String?) -> Bool {
        guard let trackID = normalizedTrackID(trackID) else {
            return false
        }

        return acceptedTrackID != trackID
    }

    mutating func accept(_ trackID: String?) {
        guard let trackID = normalizedTrackID(trackID) else {
            return
        }

        acceptedTrackID = trackID
    }

    mutating func reset() {
        acceptedTrackID = nil
    }

    private func normalizedTrackID(_ trackID: String?) -> String? {
        trackID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmptyForSpotifyPlayback
    }
}

struct SpotifyPlaybackScriptResult {
    private static let separator = "\u{1f}"

    static func snapshot(from result: String, at date: Date = Date()) -> MediaPlaybackSnapshot? {
        guard let parsed = parsed(from: result) else {
            return nil
        }

        return snapshot(from: parsed, artworkData: nil, at: date)
    }

    @MainActor
    static func snapshot(
        from result: String,
        artworkDataLoader: (URL) async -> Data?,
        at date: Date = Date()
    ) async -> MediaPlaybackSnapshot? {
        guard let parsed = parsed(from: result) else {
            return nil
        }

        let artworkData = await SpotifyArtworkData.data(
            from: parsed.artworkURL,
            loader: artworkDataLoader
        )
        return snapshot(from: parsed, artworkData: artworkData, at: date)
    }

    private struct ParsedResult {
        let playback: SpotifyPlaybackValue
        let position: Double
        let duration: Double?
        let title: String
        let artist: String
        let album: String
        let artworkURL: String?
    }

    private static func parsed(from result: String) -> ParsedResult? {
        let parts = result.components(separatedBy: separator)
        guard parts.count >= 6,
              let playback = SpotifyPlaybackValue(rawValue: parts[0]),
              playback != .stopped else {
            return nil
        }

        let title = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)
        let artworkURL = parts.indices.contains(6) ? parts[6] : nil

        guard [title, artist, album].contains(where: { $0.isEmpty == false }) else {
            return nil
        }

        return ParsedResult(
            playback: playback,
            position: max(0, Double(parts[1]) ?? 0),
            duration: SpotifyPlaybackNotice.normalizedDuration(Double(parts[2])),
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL
        )
    }

    private static func snapshot(
        from parsed: ParsedResult,
        artworkData: Data?,
        at date: Date
    ) -> MediaPlaybackSnapshot {
        return MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: parsed.title,
            artist: parsed.artist,
            album: parsed.album,
            artworkData: artworkData,
            currentTime: parsed.position,
            duration: parsed.duration,
            playbackRate: parsed.playback.isPlaying ? 1 : 0,
            isPlaying: parsed.playback.isPlaying,
            lastUpdated: date
        )
    }
}

enum SpotifyPlaybackValue: Equatable, Sendable {
    case playing
    case paused
    case stopped

    init?(rawValue: String?) {
        guard let value = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            value.isEmpty == false else {
            return nil
        }

        if value.contains("play") && value.contains("pause") == false {
            self = .playing
        } else if value.contains("pause") {
            self = .paused
        } else if value.contains("stop") {
            self = .stopped
        } else {
            return nil
        }
    }

    var isPlaying: Bool {
        self == .playing
    }
}

private extension String {
    var nilIfEmptyForSpotifyPlayback: String? {
        isEmpty ? nil : self
    }
}
