import Foundation

public enum PermissionRuleStoreError: LocalizedError {
    case configDirectoryMissing(String)
    case configParseError(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case let .configDirectoryMissing(path):
            return "Claude config directory missing at \(path)"
        case let .configParseError(detail):
            return "Failed to parse settings.json: \(detail)"
        case let .writeError(detail):
            return "Failed to write settings.json: \(detail)"
        }
    }
}

public final class PermissionRuleStore: PermissionRuleWriting, @unchecked Sendable {
    private let homeDirectoryURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        self.fileManager = fileManager
    }

    public func appendAllowRule(_ rule: ClaudePermissionRule) throws {
        lock.lock()
        defer { lock.unlock() }

        let claudeDirectoryURL = homeDirectoryURL.appendingPathComponent(".claude", isDirectory: true)
        if fileManager.fileExists(atPath: claudeDirectoryURL.path) == false {
            do {
                try fileManager.createDirectory(at: claudeDirectoryURL, withIntermediateDirectories: true)
            } catch {
                throw PermissionRuleStoreError.writeError(error.localizedDescription)
            }
        }

        let settingsURL = claudeDirectoryURL.appendingPathComponent("settings.json")
        var root = try loadJSONObjectIfPresent(at: settingsURL)
        var permissions = root["permissions"] as? [String: Any] ?? [:]
        var allow = (permissions["allow"] as? [String]) ?? []

        let ruleString = rule.ruleString
        if allow.contains(ruleString) == false {
            allow.append(ruleString)
        }

        permissions["allow"] = allow
        root["permissions"] = permissions

        try writeJSONObject(root, to: settingsURL)
    }

    private func loadJSONObjectIfPresent(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw PermissionRuleStoreError.configParseError("Expected a JSON object in \(url.path)")
            }
            return dictionary
        } catch let error as PermissionRuleStoreError {
            throw error
        } catch {
            throw PermissionRuleStoreError.configParseError(error.localizedDescription)
        }
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            throw PermissionRuleStoreError.writeError(error.localizedDescription)
        }
    }
}
