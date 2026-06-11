import AppKit
import Foundation

protocol PlaybackTimeProviding {
    func currentPlaybackTime(for source: MediaPlaybackSource) -> TimeInterval?
}

struct AppleScriptPlaybackTimeProvider: PlaybackTimeProviding {
    typealias ScriptRunner = (String) -> TimeInterval?
    typealias RunningCheck = (String) -> Bool

    private let scriptRunner: ScriptRunner
    private let isApplicationRunning: RunningCheck

    init(
        scriptRunner: @escaping ScriptRunner = Self.runAppleScript,
        isApplicationRunning: @escaping RunningCheck = Self.isApplicationRunning
    ) {
        self.scriptRunner = scriptRunner
        self.isApplicationRunning = isApplicationRunning
    }

    func currentPlaybackTime(for source: MediaPlaybackSource) -> TimeInterval? {
        guard let application = Self.supportedApplication(for: source),
              isApplicationRunning(application.bundleIdentifier) else {
            return nil
        }

        guard let playbackTime = scriptRunner(Self.script(for: application.name)),
              playbackTime >= 0 else {
            return nil
        }

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

    private static func isApplicationRunning(_ bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    private static func runAppleScript(_ source: String) -> TimeInterval? {
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
