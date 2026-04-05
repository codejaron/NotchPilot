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

        for (eventName, managedEntries) in claudeHookConfiguration(command: command) {
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

    public func installCodexHooks(bridgeScript: String) throws {
        let configDirectoryURL = homeDirectoryURL.appendingPathComponent(".codex", isDirectory: true)
        guard fileManager.fileExists(atPath: configDirectoryURL.path) else {
            throw HookInstallError.toolNotFound("Codex (~/.codex)")
        }

        let configURL = configDirectoryURL.appendingPathComponent("config.toml")
        let configContents = (try? String(contentsOf: configURL)) ?? ""
        let updatedConfig = ensureCodexHooksFeatureEnabled(in: configContents)
        do {
            try updatedConfig.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw HookInstallError.writeError(error.localizedDescription)
        }

        let hooksURL = configDirectoryURL.appendingPathComponent("hooks.json")
        var root = try loadJSONObjectIfPresent(at: hooksURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\"\(bridgeScript)\" --host codex"

        for (eventName, managedEntries) in codexHookConfiguration(command: command) {
            var eventEntries = hooks[eventName] as? [[String: Any]] ?? []
            eventEntries = removingManagedEntries(from: eventEntries, bridgeScript: bridgeScript)
            eventEntries.append(contentsOf: managedEntries)
            hooks[eventName] = eventEntries
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: hooksURL)
    }

    public func uninstallCodexHooks(bridgeScript: String? = nil) throws {
        let hooksURL = homeDirectoryURL.appendingPathComponent(".codex/hooks.json")
        guard fileManager.fileExists(atPath: hooksURL.path) else {
            return
        }

        var root = try loadJSONObject(at: hooksURL)
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
            if root.isEmpty {
                try? fileManager.removeItem(at: hooksURL)
                return
            }
        } else {
            root["hooks"] = hooks
        }

        try writeJSONObject(root, to: hooksURL)
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

    public func codexHooksInstalled(bridgeScript: String? = nil) -> Bool {
        let hooksURL = homeDirectoryURL.appendingPathComponent(".codex/hooks.json")
        guard let root = try? loadJSONObject(at: hooksURL),
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

        let settingsURL = homeDirectoryURL.appendingPathComponent(".claude/settings.json")
        guard let root = try? loadJSONObject(at: settingsURL),
              let hooks = root["hooks"] as? [String: Any],
              let entries = hooks["UserPromptSubmit"] as? [[String: Any]]
        else {
            return true
        }

        return entries.contains { isManagedEntry($0, bridgeScript: bridgeScript) } == false
    }

    public func codexHooksNeedUpdate(bridgeScript: String? = nil) -> Bool {
        guard codexHooksInstalled(bridgeScript: bridgeScript) else {
            return false
        }

        let hooksURL = homeDirectoryURL.appendingPathComponent(".codex/hooks.json")
        guard let root = try? loadJSONObject(at: hooksURL),
              let hooks = root["hooks"] as? [String: Any],
              let entries = hooks["UserPromptSubmit"] as? [[String: Any]]
        else {
            return true
        }

        return entries.contains { isManagedEntry($0, bridgeScript: bridgeScript) } == false
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
            "PreToolUse": [
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

    private func codexHookConfiguration(command: String) -> [String: [[String: Any]]] {
        [
            "PreToolUse": [
                [
                    "matcher": "Bash",
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
                    "matcher": "Bash",
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
                    "matcher": "startup|resume",
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

    private func ensureCodexHooksFeatureEnabled(in content: String) -> String {
        let pattern = try? NSRegularExpression(pattern: #"(?m)^\s*codex_hooks\s*=\s*(true|false)\s*$"#)
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)

        if let pattern, let match = pattern.firstMatch(in: content, range: nsRange),
           let range = Range(match.range, in: content) {
            var updated = content
            updated.replaceSubrange(range, with: "codex_hooks = true")
            return updated
        }

        if let featuresRange = content.range(of: "[features]") {
            var updated = content
            updated.insert(contentsOf: "\ncodex_hooks = true", at: featuresRange.upperBound)
            if updated.hasSuffix("\n") == false {
                updated.append("\n")
            }
            return updated
        }

        let separator = content.isEmpty || content.hasSuffix("\n") ? "" : "\n"
        return content + "\(separator)[features]\ncodex_hooks = true\n"
    }
}
