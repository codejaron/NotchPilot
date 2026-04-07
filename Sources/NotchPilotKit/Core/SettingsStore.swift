import Combine
import ApplicationServices
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private enum Key {
        static let claudeHookInstalled = "claude.hookInstalled"
        static let autoStartSocket = "bridge.autoStartSocket"
        static let bridgeScriptPath = "bridge.scriptPath"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    public let homeDirectoryURL: URL

    @Published public var claudeHookInstalled: Bool {
        didSet { defaults.set(claudeHookInstalled, forKey: Key.claudeHookInstalled) }
    }

    @Published public var claudeHooksNeedUpdate: Bool

    @Published public var codexDesktopConnection: CodexDesktopConnectionState
    @Published public var codexAXPermission: CodexDesktopAXPermissionState

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
        CodexDesktopAppDetector(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        ).isInstalled()
    }

    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let codexInstalled = CodexDesktopAppDetector(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        ).isInstalled()

        self.defaults = defaults
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
        self.claudeHookInstalled = defaults.object(forKey: Key.claudeHookInstalled) as? Bool ?? false
        self.claudeHooksNeedUpdate = false
        self.codexDesktopConnection = codexInstalled ? .disconnected : .notFound
        self.codexAXPermission = AXIsProcessTrusted() ? .granted : .notGranted
        self.autoStartSocket = defaults.object(forKey: Key.autoStartSocket) as? Bool ?? true
        self.bridgeScriptPath = defaults.string(forKey: Key.bridgeScriptPath) ?? ""
    }

    public func synchronizeInstallationState() {
        let installer = HookInstaller(fileManager: fileManager, homeDirectoryURL: homeDirectoryURL)
        let bridgeScript = bridgeScriptPath.isEmpty ? nil : bridgeScriptPath
        claudeHookInstalled = installer.claudeHooksInstalled(bridgeScript: bridgeScript)
        claudeHooksNeedUpdate = installer.claudeHooksNeedUpdate(bridgeScript: bridgeScript)
        if codexDetected == false {
            codexDesktopConnection = .notFound
        } else if codexDesktopConnection.status == .notFound {
            codexDesktopConnection = .disconnected
        }
    }

    public func updateCodexDesktopConnection(_ state: CodexDesktopConnectionState) {
        codexDesktopConnection = state
    }

    public func updateCodexAXPermission(_ state: CodexDesktopAXPermissionState) {
        codexAXPermission = state
    }
}
