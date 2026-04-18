import Foundation

public enum HookInstallError: LocalizedError {
    case toolNotFound(String)
    case configParseError(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case let .toolNotFound(tool):
            return "\(tool) config directory not found"
        case let .configParseError(detail):
            return "Config parse error: \(detail)"
        case let .writeError(detail):
            return "Write error: \(detail)"
        }
    }
}

public struct HookInstaller {
    private static let bridgeVersionNeedle = "NOTCHPILOT_BRIDGE_VERSION = 2"

    private let fileManager: FileManager
    public let homeDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
    }

    public func installClaudeHooks(bridgeScript: String) throws {
        let configDirectoryURL = homeDirectoryURL.appendingPathComponent(".claude", isDirectory: true)
        guard fileManager.fileExists(atPath: configDirectoryURL.path) else {
            throw HookInstallError.toolNotFound("Claude Code (~/.claude)")
        }

        let settingsURL = configDirectoryURL.appendingPathComponent("settings.json")
        var root = try loadJSONObjectIfPresent(at: settingsURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\"\(bridgeScript)\" --host claude"
        let configuration = claudeHookConfiguration(command: command)
        let managedEventNames = Set(configuration.keys)

        for eventName in Array(hooks.keys) where managedEventNames.contains(eventName) == false {
            guard let entries = hooks[eventName] as? [[String: Any]] else { continue }
            let filtered = removingManagedEntries(from: entries, bridgeScript: bridgeScript)
            if filtered.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = filtered
            }
        }

        for (eventName, managedEntries) in configuration {
            var eventEntries = hooks[eventName] as? [[String: Any]] ?? []
            eventEntries = removingManagedEntries(from: eventEntries, bridgeScript: bridgeScript)
            eventEntries.append(contentsOf: managedEntries)
            hooks[eventName] = eventEntries
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: settingsURL)
    }

    public func uninstallClaudeHooks(bridgeScript: String? = nil) throws {
        let settingsURL = homeDirectoryURL.appendingPathComponent(".claude/settings.json")
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return
        }

        var root = try loadJSONObject(at: settingsURL)
        guard var hooks = root["hooks"] as? [String: Any] else {
            return
        }

        for eventName in hooks.keys.sorted() {
            guard let entries = hooks[eventName] as? [[String: Any]] else { continue }
            let filteredEntries = removingManagedEntries(from: entries, bridgeScript: bridgeScript)
            if filteredEntries.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = filteredEntries
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }

        try writeJSONObject(root, to: settingsURL)
    }

    public func installBridgeScript(fromBundle bundlePath: String) throws -> String {
        let targetDirectoryURL = homeDirectoryURL.appendingPathComponent(".notchpilot", isDirectory: true)
        do {
            try fileManager.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw HookInstallError.writeError(error.localizedDescription)
        }

        let targetURL = targetDirectoryURL.appendingPathComponent("notch-bridge.py")
        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }

        do {
            try fileManager.copyItem(atPath: bundlePath, toPath: targetURL.path)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)
        } catch {
            throw HookInstallError.writeError(error.localizedDescription)
        }

        return targetURL.path
    }

    public func claudeHooksInstalled(bridgeScript: String? = nil) -> Bool {
        let settingsURL = homeDirectoryURL.appendingPathComponent(".claude/settings.json")
        guard let root = try? loadJSONObject(at: settingsURL),
              let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else {
                return false
            }
            return entries.contains { isManagedEntry($0, bridgeScript: bridgeScript) }
        }
    }

    public func claudeHooksNeedUpdate(bridgeScript: String? = nil) -> Bool {
        guard claudeHooksInstalled(bridgeScript: bridgeScript) else {
            return false
        }

        if installedBridgeScriptNeedsUpdate(bridgeScript) {
            return true
        }

        let settingsURL = homeDirectoryURL.appendingPathComponent(".claude/settings.json")
        guard let root = try? loadJSONObject(at: settingsURL),
              let hooks = root["hooks"] as? [String: Any]
        else {
            return true
        }

        let managedEventNames = Set(claudeHookConfiguration(command: "").keys)

        for (eventName, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let hasManaged = entries.contains { isManagedEntry($0, bridgeScript: bridgeScript) }
            if hasManaged, managedEventNames.contains(eventName) == false {
                return true
            }
        }

        for eventName in managedEventNames {
            guard let entries = hooks[eventName] as? [[String: Any]],
                  entries.contains(where: { isManagedEntry($0, bridgeScript: bridgeScript) })
            else {
                return true
            }
        }

        return false
    }

    private func installedBridgeScriptNeedsUpdate(_ bridgeScript: String?) -> Bool {
        guard let bridgeScript,
              bridgeScript.isEmpty == false,
              fileManager.fileExists(atPath: bridgeScript),
              let script = try? String(contentsOfFile: bridgeScript, encoding: .utf8)
        else {
            return false
        }

        return script.contains(Self.bridgeVersionNeedle) == false
    }

    private func claudeHookConfiguration(command: String) -> [String: [[String: Any]]] {
        [
            "PermissionRequest": [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": command,
                            "timeout": 300,
                        ],
                    ],
                ],
            ],
            "PostToolUse": [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": command,
                        ],
                    ],
                ],
            ],
            "SessionStart": [
                [
                    "hooks": [
                        [
                            "type": "command",
                            "command": command,
                        ],
                    ],
                ],
            ],
            "Stop": [
                [
                    "hooks": [
                        [
                            "type": "command",
                            "command": command,
                        ],
                    ],
                ],
            ],
            "UserPromptSubmit": [
                [
                    "hooks": [
                        [
                            "type": "command",
                            "command": command,
                        ],
                    ],
                ],
            ],
        ]
    }

    private func loadJSONObjectIfPresent(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }
        return try loadJSONObject(at: url)
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw HookInstallError.configParseError("Expected a JSON object in \(url.path)")
            }
            return dictionary
        } catch let error as HookInstallError {
            throw error
        } catch {
            throw HookInstallError.configParseError(error.localizedDescription)
        }
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
        } catch {
            throw HookInstallError.writeError(error.localizedDescription)
        }
    }

    private func removingManagedEntries(from entries: [[String: Any]], bridgeScript: String?) -> [[String: Any]] {
        entries.filter { isManagedEntry($0, bridgeScript: bridgeScript) == false }
    }

    private func isManagedEntry(_ entry: [String: Any], bridgeScript: String?) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else {
            return false
        }

        let commandNeedle = bridgeScript?.isEmpty == false ? bridgeScript! : "notch-bridge.py"
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else {
                return false
            }
            return command.contains(commandNeedle)
        }
    }
}
