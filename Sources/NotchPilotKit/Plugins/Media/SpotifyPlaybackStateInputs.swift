import AppKit
import Foundation

protocol SpotifyPlaybackSnapshotProviding {
    func currentSpotifyPlaybackSnapshot(at date: Date) -> MediaPlaybackSnapshot?
}

struct AppleScriptSpotifyPlaybackSnapshotProvider: SpotifyPlaybackSnapshotProviding {
    typealias ScriptRunner = (String) -> String?
    typealias RunningCheck = () -> Bool

    private let scriptRunner: ScriptRunner
    private let isSpotifyRunning: RunningCheck

    init(
        scriptRunner: @escaping ScriptRunner = Self.runAppleScript,
        isSpotifyRunning: @escaping RunningCheck = Self.isSpotifyRunning
    ) {
        self.scriptRunner = scriptRunner
        self.isSpotifyRunning = isSpotifyRunning
    }

    func currentSpotifyPlaybackSnapshot(at date: Date = Date()) -> MediaPlaybackSnapshot? {
        guard isSpotifyRunning() else {
            return nil
        }

        guard let result = scriptRunner(Self.script) else {
            return nil
        }

        return SpotifyPlaybackScriptResult.snapshot(from: result, at: date)
    }

    private static let script = """
    set sep to ASCII character 31
    tell application "Spotify"
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set trackDuration to duration of current track
        set trackPosition to player position
        set trackState to player state as string
        return trackState & sep & trackPosition & sep & trackDuration & sep & trackName & sep & trackArtist & sep & trackAlbum
    end tell
    """

    private static func isSpotifyRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty == false
    }

    private static func runAppleScript(_ source: String) -> String? {
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
}

enum SpotifyPlaybackNotice {
    struct Payload: Sendable {
        let playback: SpotifyPlaybackValue
        let title: String?
        let artist: String?
        let album: String?
        let position: TimeInterval?
        let duration: TimeInterval?
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
            duration: numberValue(for: "Duration", in: userInfo)
        )
    }

    static func state(
        from userInfo: [AnyHashable: Any],
        fallback: MediaPlaybackSnapshot?,
        at date: Date = Date()
    ) -> MediaPlaybackState? {
        guard let payload = payload(from: userInfo) else {
            return nil
        }

        return state(from: payload, fallback: fallback, at: date)
    }

    static func state(
        from payload: Payload,
        fallback: MediaPlaybackSnapshot?,
        at date: Date = Date()
    ) -> MediaPlaybackState? {
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

        return .active(
            MediaPlaybackSnapshot(
                source: .fromBundleIdentifier("com.spotify.client"),
                title: title,
                artist: artist,
                album: album,
                artworkData: fallback?.artworkData,
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
}

struct SpotifyPlaybackScriptResult {
    private static let separator = "\u{1f}"

    static func snapshot(from result: String, at date: Date = Date()) -> MediaPlaybackSnapshot? {
        let parts = result.components(separatedBy: separator)
        guard parts.count >= 6,
              let playback = SpotifyPlaybackValue(rawValue: parts[0]),
              playback != .stopped else {
            return nil
        }

        let title = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)

        guard [title, artist, album].contains(where: { $0.isEmpty == false }) else {
            return nil
        }

        return MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: title,
            artist: artist,
            album: album,
            artworkData: nil,
            currentTime: max(0, Double(parts[1]) ?? 0),
            duration: SpotifyPlaybackNotice.normalizedDuration(Double(parts[2])),
            playbackRate: playback.isPlaying ? 1 : 0,
            isPlaying: playback.isPlaying,
            lastUpdated: date
        )
    }
}

struct MediaPlaybackStateSelector {
    private var systemState: MediaPlaybackState = .idle
    private var spotifyState: MediaPlaybackState = .idle

    var spotifySnapshot: MediaPlaybackSnapshot? {
        guard case let .active(snapshot) = spotifyState else {
            return nil
        }
        return snapshot
    }

    mutating func acceptSystem(_ state: MediaPlaybackState, at date: Date = Date()) -> MediaPlaybackState {
        systemState = Self.projected(state, at: date)
        return selectedState(at: date)
    }

    mutating func acceptSpotify(_ state: MediaPlaybackState, at date: Date = Date()) -> MediaPlaybackState {
        spotifyState = Self.projected(state, at: date)
        return selectedState(at: date)
    }

    mutating func reset() {
        systemState = .idle
        spotifyState = .idle
    }

    func selectedState(at date: Date = Date()) -> MediaPlaybackState {
        let systemState = Self.projected(systemState, at: date)
        let spotifyState = Self.projected(spotifyState, at: date)
        let systemSnapshot = Self.snapshot(from: systemState)
        let spotifySnapshot = Self.snapshot(from: spotifyState)

        if let systemSnapshot,
           systemSnapshot.isPlaying,
           Self.isSpotify(systemSnapshot.source) == false {
            return .active(systemSnapshot)
        }

        if let spotifySnapshot, spotifySnapshot.isPlaying {
            return .active(spotifySnapshot)
        }

        if let systemSnapshot, systemSnapshot.isPlaying {
            return .active(systemSnapshot)
        }

        if let systemSnapshot,
           Self.isSpotify(systemSnapshot.source) == false {
            return .active(systemSnapshot)
        }

        if let spotifySnapshot {
            return .active(spotifySnapshot)
        }

        if case .unavailable = systemState {
            return .unavailable
        }

        return .idle
    }

    private static func isSpotify(_ source: MediaPlaybackSource) -> Bool {
        source.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("spotify") == true ||
            source.displayName.lowercased().contains("spotify")
    }

    private static func snapshot(from state: MediaPlaybackState) -> MediaPlaybackSnapshot? {
        guard case let .active(snapshot) = state else {
            return nil
        }
        return snapshot
    }

    private static func projected(_ state: MediaPlaybackState, at date: Date) -> MediaPlaybackState {
        guard case let .active(snapshot) = state else {
            return state
        }
        return .active(snapshot.replacingCurrentTime(snapshot.estimatedCurrentTime(at: date), at: date))
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
