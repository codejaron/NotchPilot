import Combine
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private enum Key {
        static let claudeHookInstalled = "claude.hookInstalled"
        static let codexHookInstalled = "codex.hookInstalled"
        static let autoStartSocket = "bridge.autoStartSocket"
        static let bridgeScriptPath = "bridge.scriptPath"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    public let homeDirectoryURL: URL

    @Published public var claudeHookInstalled: Bool {
        didSet { defaults.set(claudeHookInstalled, forKey: Key.claudeHookInstalled) }
    }

    @Published public var codexHookInstalled: Bool {
        didSet { defaults.set(codexHookInstalled, forKey: Key.codexHookInstalled) }
    }

    @Published public var claudeHooksNeedUpdate: Bool

    @Published public var codexHooksNeedUpdate: Bool

    @Published public var autoStartSocket: Bool {
        didSet {
            defaults.set(autoStartSocket, forKey: Key.autoStartSocket)
            NotificationCenter.default.post(name: .bridgeSocketPreferenceChanged, object: autoStartSocket)
        }
    }

    @Published public var bridgeScriptPath: String {
        didSet { defaults.set(bridgeScriptPath, forKey: Key.bridgeScriptPath) }
    }

    public var claudeCodeDetected: Bool {
        fileManager.fileExists(atPath: homeDirectoryURL.appendingPathComponent(".claude", isDirectory: true).path)
    }

    public var codexDetected: Bool {
        fileManager.fileExists(atPath: homeDirectoryURL.appendingPathComponent(".codex", isDirectory: true).path)
    }

    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
        self.claudeHookInstalled = defaults.object(forKey: Key.claudeHookInstalled) as? Bool ?? false
        self.codexHookInstalled = defaults.object(forKey: Key.codexHookInstalled) as? Bool ?? false
        self.claudeHooksNeedUpdate = false
        self.codexHooksNeedUpdate = false
        self.autoStartSocket = defaults.object(forKey: Key.autoStartSocket) as? Bool ?? true
        self.bridgeScriptPath = defaults.string(forKey: Key.bridgeScriptPath) ?? ""
    }

    public func synchronizeInstallationState() {
        let installer = HookInstaller(fileManager: fileManager, homeDirectoryURL: homeDirectoryURL)
        let bridgeScript = bridgeScriptPath.isEmpty ? nil : bridgeScriptPath
        claudeHookInstalled = installer.claudeHooksInstalled(bridgeScript: bridgeScript)
        codexHookInstalled = installer.codexHooksInstalled(bridgeScript: bridgeScript)
        claudeHooksNeedUpdate = installer.claudeHooksNeedUpdate(bridgeScript: bridgeScript)
        codexHooksNeedUpdate = installer.codexHooksNeedUpdate(bridgeScript: bridgeScript)
    }
}
