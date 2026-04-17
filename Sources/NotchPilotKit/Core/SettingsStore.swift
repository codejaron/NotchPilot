import Combine
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private enum Key {
        static let claudeHookInstalled = "claude.hookInstalled"
        static let autoStartSocket = "bridge.autoStartSocket"
        static let bridgeScriptPath = "bridge.scriptPath"
        static let approvalSneakNotificationsEnabled = "approval.sneakNotificationsEnabled"
        static let mediaPlaybackEnabled = "media.enabled"
        static let mediaPlaybackSneakPreviewEnabled = "media.sneakPreviewEnabled"
        static let desktopLyricsEnabled = "media.desktopLyricsEnabled"
        static let desktopLyricsHighlightColorHex = "media.desktopLyricsHighlightColorHex"
        static let desktopLyricsFontSize = "media.desktopLyricsFontSize"
        static let systemMonitorSneakPreviewEnabled = "systemMonitor.sneakPreviewEnabled"
        static let systemMonitorSneakLeftMetrics = "systemMonitor.sneak.leftMetrics"
        static let systemMonitorSneakRightMetrics = "systemMonitor.sneak.rightMetrics"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    public let homeDirectoryURL: URL

    @Published public var claudeHookInstalled: Bool {
        didSet { defaults.set(claudeHookInstalled, forKey: Key.claudeHookInstalled) }
    }

    @Published public var claudeHooksNeedUpdate: Bool

    @Published public var codexDesktopConnection: CodexDesktopConnectionState

    @Published public var autoStartSocket: Bool {
        didSet {
            defaults.set(autoStartSocket, forKey: Key.autoStartSocket)
            NotificationCenter.default.post(name: .bridgeSocketPreferenceChanged, object: autoStartSocket)
        }
    }

    @Published public var bridgeScriptPath: String {
        didSet { defaults.set(bridgeScriptPath, forKey: Key.bridgeScriptPath) }
    }

    @Published public var approvalSneakNotificationsEnabled: Bool {
        didSet {
            defaults.set(approvalSneakNotificationsEnabled, forKey: Key.approvalSneakNotificationsEnabled)
        }
    }

    @Published var mediaPlaybackEnabled: Bool {
        didSet {
            defaults.set(mediaPlaybackEnabled, forKey: Key.mediaPlaybackEnabled)
        }
    }

    @Published var mediaPlaybackSneakPreviewEnabled: Bool {
        didSet {
            defaults.set(mediaPlaybackSneakPreviewEnabled, forKey: Key.mediaPlaybackSneakPreviewEnabled)
        }
    }

    @Published var desktopLyricsEnabled: Bool {
        didSet {
            defaults.set(desktopLyricsEnabled, forKey: Key.desktopLyricsEnabled)
        }
    }

    @Published var desktopLyricsHighlightColorHex: String {
        didSet {
            defaults.set(desktopLyricsHighlightColorHex, forKey: Key.desktopLyricsHighlightColorHex)
        }
    }

    @Published var desktopLyricsFontSize: Double {
        didSet {
            defaults.set(desktopLyricsFontSize, forKey: Key.desktopLyricsFontSize)
        }
    }

    @Published var systemMonitorSneakPreviewEnabled: Bool {
        didSet {
            defaults.set(systemMonitorSneakPreviewEnabled, forKey: Key.systemMonitorSneakPreviewEnabled)
        }
    }

    @Published var systemMonitorSneakConfiguration: SystemMonitorSneakConfiguration {
        didSet {
            persistSystemMonitorSneakConfiguration(systemMonitorSneakConfiguration)
        }
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
        self.autoStartSocket = defaults.object(forKey: Key.autoStartSocket) as? Bool ?? true
        self.bridgeScriptPath = defaults.string(forKey: Key.bridgeScriptPath) ?? ""
        self.approvalSneakNotificationsEnabled =
            defaults.object(forKey: Key.approvalSneakNotificationsEnabled) as? Bool ?? true
        self.mediaPlaybackEnabled =
            defaults.object(forKey: Key.mediaPlaybackEnabled) as? Bool ?? true
        self.mediaPlaybackSneakPreviewEnabled =
            defaults.object(forKey: Key.mediaPlaybackSneakPreviewEnabled) as? Bool ?? true
        self.desktopLyricsEnabled =
            defaults.object(forKey: Key.desktopLyricsEnabled) as? Bool ?? false
        self.desktopLyricsHighlightColorHex =
            defaults.string(forKey: Key.desktopLyricsHighlightColorHex) ?? "#4ADE80"
        self.desktopLyricsFontSize =
            defaults.object(forKey: Key.desktopLyricsFontSize) as? Double ?? 28
        self.systemMonitorSneakPreviewEnabled =
            defaults.object(forKey: Key.systemMonitorSneakPreviewEnabled) as? Bool ?? true
        self.systemMonitorSneakConfiguration = Self.systemMonitorSneakConfiguration(from: defaults)
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

    private static func systemMonitorSneakConfiguration(from defaults: UserDefaults) -> SystemMonitorSneakConfiguration {
        let defaultConfiguration = SystemMonitorSneakConfiguration.default
        return SystemMonitorSneakConfiguration(
            left: systemMonitorMetrics(
                from: defaults,
                key: Key.systemMonitorSneakLeftMetrics,
                fallback: defaultConfiguration.leftMetrics
            ),
            right: systemMonitorMetrics(
                from: defaults,
                key: Key.systemMonitorSneakRightMetrics,
                fallback: defaultConfiguration.rightMetrics
            )
        )
    }

    private static func systemMonitorMetrics(
        from defaults: UserDefaults,
        key: String,
        fallback: [SystemMonitorMetric]
    ) -> [SystemMonitorMetric] {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }

        return defaults.stringArray(forKey: key)?
            .compactMap(SystemMonitorMetric.init(rawValue:)) ?? []
    }

    private func persistSystemMonitorSneakConfiguration(_ configuration: SystemMonitorSneakConfiguration) {
        defaults.set(configuration.leftMetrics.map(\.rawValue), forKey: Key.systemMonitorSneakLeftMetrics)
        defaults.set(configuration.rightMetrics.map(\.rawValue), forKey: Key.systemMonitorSneakRightMetrics)
    }
}
