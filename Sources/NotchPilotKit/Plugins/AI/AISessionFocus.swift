import AppKit
import Foundation

public enum AISessionFocusFallback: Equatable, Sendable {
    case host(AIHost)
    case codexThread(String)
}

public protocol AISessionFocusing: AnyObject {
    @discardableResult
    func focus(context: AISessionLaunchContext, fallback: AISessionFocusFallback) -> Bool

    @discardableResult
    func focusCodexThread(id: String, fallbackContext: AISessionLaunchContext?) -> Bool
}

public final class SystemAISessionFocuser: AISessionFocusing {
    public init() {}

    @discardableResult
    public func focus(context: AISessionLaunchContext, fallback: AISessionFocusFallback) -> Bool {
        if let terminalIdentifier = context.terminalIdentifier,
           focusTerminal(terminalIdentifier: terminalIdentifier, preferredBundleIdentifier: context.bundleIdentifier) {
            return true
        }

        if let processIdentifier = context.processIdentifier,
           let runningApplication = NSRunningApplication(processIdentifier: processIdentifier),
           activate(runningApplication) {
            return true
        }

        if let bundleIdentifier = context.bundleIdentifier,
           activateApplication(bundleIdentifier: bundleIdentifier) {
            return true
        }

        return focusFallback(fallback)
    }

    @discardableResult
    public func focusCodexThread(id: String, fallbackContext: AISessionLaunchContext?) -> Bool {
        if let fallbackContext,
           fallbackContext.terminalIdentifier != nil,
           focus(context: fallbackContext, fallback: .host(.codex)) {
            return true
        }

        if openCodexThread(id: id) {
            return true
        }

        if let fallbackContext,
           focus(context: fallbackContext, fallback: .host(.codex)) {
            return true
        }

        return focus(context: AISessionLaunchContext(), fallback: .host(.codex))
    }

    private func focusFallback(_ fallback: AISessionFocusFallback) -> Bool {
        switch fallback {
        case let .host(host):
            return hostFallbackBundleIdentifiers(host).contains(where: activateApplication(bundleIdentifier:))
        case let .codexThread(threadID):
            return openCodexThread(id: threadID)
        }
    }

    private func focusTerminal(
        terminalIdentifier: String,
        preferredBundleIdentifier: String?
    ) -> Bool {
        let terminalBundleIdentifiers = orderedTerminalBundleIdentifiers(preferredBundleIdentifier)

        for bundleIdentifier in terminalBundleIdentifiers {
            switch bundleIdentifier {
            case "com.apple.Terminal":
                if focusTerminalAppTab(terminalIdentifier: terminalIdentifier) {
                    return true
                }
            case "com.googlecode.iterm2":
                if focusITermSession(terminalIdentifier: terminalIdentifier) {
                    return true
                }
            default:
                if activateApplication(bundleIdentifier: bundleIdentifier) {
                    return true
                }
            }
        }

        return false
    }

    private func orderedTerminalBundleIdentifiers(_ preferredBundleIdentifier: String?) -> [String] {
        let known = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "com.microsoft.VSCode",
        ]

        guard let preferredBundleIdentifier,
              known.contains(preferredBundleIdentifier)
        else {
            return known
        }

        return [preferredBundleIdentifier] + known.filter { $0 != preferredBundleIdentifier }
    }

    private func focusTerminalAppTab(terminalIdentifier: String) -> Bool {
        let tty = terminalIdentifier.removingDevPrefix
        let script = """
        set targetTTY to \(appleScriptLiteral(tty))
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabTTY to tty of t
                    if tabTTY is targetTTY or tabTTY is "/dev/" & targetTTY then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        error "terminal tty not found"
        """

        return runAppleScript(script)
    }

    private func focusITermSession(terminalIdentifier: String) -> Bool {
        let tty = terminalIdentifier.removingDevPrefix
        let script = """
        set targetTTY to \(appleScriptLiteral(tty))
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionTTY to tty of s
                        if sessionTTY is targetTTY or sessionTTY is "/dev/" & targetTTY then
                            select t
                            select s
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        error "iterm tty not found"
        """

        return runAppleScript(script)
    }

    private func activateApplication(bundleIdentifier: String) -> Bool {
        if let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first,
            activate(runningApplication) {
            return true
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
        return true
    }

    private func activate(_ runningApplication: NSRunningApplication) -> Bool {
        runningApplication.activate(options: [.activateAllWindows])
    }

    private func openCodexThread(id: String) -> Bool {
        let allowedCharacters = CharacterSet.urlPathAllowed
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              let url = URL(string: "codex://threads/\(encodedID)")
        else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }

    private func hostFallbackBundleIdentifiers(_ host: AIHost) -> [String] {
        switch host {
        case .claude:
            return [
                "com.anthropic.claude",
                "com.anthropic.claudefordesktop",
            ]
        case .codex:
            return [
                "com.openai.codex",
            ]
        }
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private extension String {
    var removingDevPrefix: String {
        if hasPrefix("/dev/") {
            return String(dropFirst("/dev/".count))
        }

        return self
    }
}
