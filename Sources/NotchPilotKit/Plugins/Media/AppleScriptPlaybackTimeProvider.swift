import AppKit
import Foundation

protocol PlaybackTimeProviding {
    @MainActor
    func currentPlaybackTime(for source: MediaPlaybackSource) async -> TimeInterval?
}

actor PlaybackTimeCache {
    private var entries: [String: (value: TimeInterval, date: Date)] = [:]

    func value(for key: String, now: Date, duration: TimeInterval) -> TimeInterval? {
        guard let entry = entries[key],
              now.timeIntervalSince(entry.date) <= duration else {
            return nil
        }
        return entry.value
    }

    func store(_ value: TimeInterval, for key: String, at date: Date) {
        entries[key] = (value, date)
    }
}

struct AppleScriptPlaybackTimeProvider: PlaybackTimeProviding {
    typealias ScriptRunner = (String) async -> TimeInterval?
    typealias RunningCheck = (String) -> Bool

    private let scriptRunner: ScriptRunner
    private let isApplicationRunning: RunningCheck
    private let cacheDuration: TimeInterval
    private let now: () -> Date
    private let cache = PlaybackTimeCache()

    init(
        scriptRunner: @escaping ScriptRunner = Self.runAppleScript,
        isApplicationRunning: @escaping RunningCheck = Self.isApplicationRunning,
        cacheDuration: TimeInterval = 0.75,
        now: @escaping () -> Date = Date.init
    ) {
        self.scriptRunner = scriptRunner
        self.isApplicationRunning = isApplicationRunning
        self.cacheDuration = cacheDuration
        self.now = now
    }

    @MainActor
    func currentPlaybackTime(for source: MediaPlaybackSource) async -> TimeInterval? {
        guard let application = Self.supportedApplication(for: source),
              isApplicationRunning(application.bundleIdentifier) else {
            return nil
        }

        let date = now()
        let key = Self.cacheKey(for: source)
        if let cachedValue = await cache.value(for: key, now: date, duration: cacheDuration) {
            return cachedValue
        }

        guard let playbackTime = await scriptRunner(Self.script(for: application.name)),
              playbackTime >= 0 else {
            return nil
        }

        await cache.store(playbackTime, for: key, at: date)
        return playbackTime
    }

    private struct ScriptablePlaybackApplication {
        let bundleIdentifier: String
        let name: String
    }

    private static func supportedApplication(for source: MediaPlaybackSource) -> ScriptablePlaybackApplication? {
        let normalizedBundleIdentifier = source.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedBundleIdentifier {
        case "com.spotify.client":
            return ScriptablePlaybackApplication(bundleIdentifier: "com.spotify.client", name: "Spotify")
        case "com.apple.music":
            return ScriptablePlaybackApplication(bundleIdentifier: "com.apple.Music", name: "Music")
        case "com.apple.itunes":
            return ScriptablePlaybackApplication(bundleIdentifier: "com.apple.iTunes", name: "iTunes")
        default:
            return nil
        }
    }

    private static func script(for applicationName: String) -> String {
        """
        tell application "\(applicationName)" to return player position
        """
    }

    private static func cacheKey(for source: MediaPlaybackSource) -> String {
        "\(source.bundleIdentifier ?? "")|\(source.displayName)"
    }

    private static func isApplicationRunning(_ bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    private static func runAppleScript(_ source: String) async -> TimeInterval? {
        await Task.detached(priority: .utility) {
            guard let script = NSAppleScript(source: source) else {
                return nil
            }

            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            guard error == nil else {
                return nil
            }

            return result.doubleValue
        }.value
    }
}
