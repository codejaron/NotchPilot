import Foundation

protocol PlaybackTimeProviding {
    func currentPlaybackTime(for source: MediaPlaybackSource) -> TimeInterval?
}

struct AppleScriptPlaybackTimeProvider: PlaybackTimeProviding {
    typealias ScriptRunner = (String) -> TimeInterval?

    private let scriptRunner: ScriptRunner

    init(scriptRunner: @escaping ScriptRunner = Self.runAppleScript) {
        self.scriptRunner = scriptRunner
    }

    func currentPlaybackTime(for source: MediaPlaybackSource) -> TimeInterval? {
        guard let bundleIdentifier = Self.supportedBundleIdentifier(for: source) else {
            return nil
        }

        guard let playbackTime = scriptRunner(Self.script(for: bundleIdentifier)),
              playbackTime >= 0 else {
            return nil
        }

        return playbackTime
    }

    private static func supportedBundleIdentifier(for source: MediaPlaybackSource) -> String? {
        let normalizedBundleIdentifier = source.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedBundleIdentifier {
        case "com.spotify.client":
            return "com.spotify.client"
        case "com.apple.music":
            return "com.apple.Music"
        case "com.apple.itunes":
            return "com.apple.iTunes"
        default:
            return nil
        }
    }

    private static func script(for bundleIdentifier: String) -> String {
        """
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)" to return player position
        else
            return -1
        end if
        """
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
