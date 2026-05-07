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
        static let activitySneakPreviewsHidden = "sneak.activityPreviewsHidden"
        static let mediaPlaybackEnabled = "media.enabled"
        static let mediaPlaybackSneakPreviewEnabled = "media.sneakPreviewEnabled"
        static let desktopLyricsEnabled = "media.desktopLyricsEnabled"
        static let desktopLyricsHighlightColorHex = "media.desktopLyricsHighlightColorHex"
        static let desktopLyricsFontSize = "media.desktopLyricsFontSize"
        static let systemMonitorEnabled = "systemMonitor.enabled"
        static let systemMonitorSneakPreviewEnabled = "systemMonitor.sneakPreviewEnabled"
        static let systemMonitorSneakLeftMetrics = "systemMonitor.sneak.leftMetrics"
        static let systemMonitorSneakRightMetrics = "systemMonitor.sneak.rightMetrics"
        static let systemMonitorSneakMode = "systemMonitor.sneak.mode"
        static let systemMonitorSneakReactiveMetrics = "systemMonitor.sneak.reactiveMetrics"
        static let systemMonitorAlertCpuPercent = "systemMonitor.alertThreshold.cpu"
        static let systemMonitorAlertMemoryPercent = "systemMonitor.alertThreshold.memory"
        static let systemMonitorAlertTemperatureCelsius = "systemMonitor.alertThreshold.temperature"
        static let systemMonitorAlertBatteryPercent = "systemMonitor.alertThreshold.battery"
        static let systemMonitorAlertDiskFreeGB = "systemMonitor.alertThreshold.disk"
        static let systemMonitorAlertNetworkMBps = "systemMonitor.alertThreshold.network"
        static let claudePluginEnabled = "claude.enabled"
        static let codexPluginEnabled = "codex.enabled"
        static let interfaceLanguage = "app.interfaceLanguage"
        static let soundEnabled = "sound.enabled"
        static let soundVolume = "sound.volume"
        static let soundTaskCompleteVolume = "sound.taskCompleteVolume"
        static let soundInputRequiredVolume = "sound.inputRequiredVolume"
        static let soundActivePackID = "sound.activePackID"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    public let homeDirectoryURL: URL
    private let launchAtLoginController: LaunchAtLoginControlling
    private var isSyncingLaunchAtLogin = false

    @Published public var claudeHookInstalled: Bool {
        didSet { defaults.set(claudeHookInstalled, forKey: Key.claudeHookInstalled) }
    }

    @Published public var claudeHooksNeedUpdate: Bool

    @Published public var codexDesktopConnection: CodexDesktopConnectionState

    @Published public var interfaceLanguage: AppLanguage {
        didSet {
            defaults.set(interfaceLanguage.rawValue, forKey: Key.interfaceLanguage)
        }
    }

    @Published public var autoStartSocket: Bool {
        didSet {
            defaults.set(autoStartSocket, forKey: Key.autoStartSocket)
            NotificationCenter.default.post(name: .bridgeSocketPreferenceChanged, object: autoStartSocket)
        }
    }

    @Published public var launchAtLoginEnabled: Bool {
        didSet {
            guard isSyncingLaunchAtLogin == false else { return }
            do {
                try launchAtLoginController.setEnabled(launchAtLoginEnabled)
            } catch {
                NSLog("NotchPilot failed to update login item: \(error.localizedDescription)")
                isSyncingLaunchAtLogin = true
                launchAtLoginEnabled = oldValue
                isSyncingLaunchAtLogin = false
            }
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

    @Published var activitySneakPreviewsHidden: Bool {
        didSet {
            defaults.set(activitySneakPreviewsHidden, forKey: Key.activitySneakPreviewsHidden)
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

    @Published var systemMonitorEnabled: Bool {
        didSet {
            defaults.set(systemMonitorEnabled, forKey: Key.systemMonitorEnabled)
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

    @Published var systemMonitorAlertThresholds: SystemMonitorAlertThresholds {
        didSet {
            persistSystemMonitorAlertThresholds(systemMonitorAlertThresholds)
        }
    }

    @Published var claudePluginEnabled: Bool {
        didSet {
            defaults.set(claudePluginEnabled, forKey: Key.claudePluginEnabled)
        }
    }

    @Published var codexPluginEnabled: Bool {
        didSet {
            defaults.set(codexPluginEnabled, forKey: Key.codexPluginEnabled)
        }
    }

    @Published public var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: Key.soundEnabled)
        }
    }

    @Published public var soundTaskCompleteVolume: Double {
        didSet {
            defaults.set(soundTaskCompleteVolume, forKey: Key.soundTaskCompleteVolume)
        }
    }

    @Published public var soundInputRequiredVolume: Double {
        didSet {
            defaults.set(soundInputRequiredVolume, forKey: Key.soundInputRequiredVolume)
        }
    }

    @Published public var soundActivePackID: String {
        didSet {
            defaults.set(soundActivePackID, forKey: Key.soundActivePackID)
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
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        launchAtLoginController: LaunchAtLoginControlling = SMAppServiceLaunchAtLoginController()
    ) {
        let codexInstalled = CodexDesktopAppDetector(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        ).isInstalled()

        self.defaults = defaults
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
        self.launchAtLoginController = launchAtLoginController
        self.launchAtLoginEnabled = launchAtLoginController.isEnabled()
        self.claudeHookInstalled = defaults.object(forKey: Key.claudeHookInstalled) as? Bool ?? false
        self.claudeHooksNeedUpdate = false
        self.codexDesktopConnection = codexInstalled ? .disconnected : .notFound
        self.interfaceLanguage = AppLanguage(rawValue: defaults.string(forKey: Key.interfaceLanguage) ?? "")
            ?? .zhHans
        self.autoStartSocket = defaults.object(forKey: Key.autoStartSocket) as? Bool ?? true
        self.bridgeScriptPath = defaults.string(forKey: Key.bridgeScriptPath) ?? ""
        self.approvalSneakNotificationsEnabled =
            defaults.object(forKey: Key.approvalSneakNotificationsEnabled) as? Bool ?? true
        self.activitySneakPreviewsHidden =
            defaults.object(forKey: Key.activitySneakPreviewsHidden) as? Bool ?? false
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
        self.systemMonitorEnabled =
            defaults.object(forKey: Key.systemMonitorEnabled) as? Bool ?? true
        self.systemMonitorSneakPreviewEnabled =
            defaults.object(forKey: Key.systemMonitorSneakPreviewEnabled) as? Bool ?? true
        self.systemMonitorSneakConfiguration = Self.systemMonitorSneakConfiguration(from: defaults)
        self.systemMonitorAlertThresholds = Self.systemMonitorAlertThresholds(from: defaults)
        self.claudePluginEnabled =
            defaults.object(forKey: Key.claudePluginEnabled) as? Bool ?? true
        self.codexPluginEnabled =
            defaults.object(forKey: Key.codexPluginEnabled) as? Bool ?? true
        self.soundEnabled =
            defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        // Migrate the legacy unified `sound.volume` value: if the user had a
        // single volume previously, reuse it as the default for both new
        // sliders so their preference carries over on first launch.
        let legacySoundVolume = defaults.object(forKey: Key.soundVolume) as? Double
        self.soundTaskCompleteVolume =
            defaults.object(forKey: Key.soundTaskCompleteVolume) as? Double
            ?? legacySoundVolume
            ?? 0.6
        self.soundInputRequiredVolume =
            defaults.object(forKey: Key.soundInputRequiredVolume) as? Double
            ?? legacySoundVolume
            ?? 0.6
        self.soundActivePackID =
            defaults.string(forKey: Key.soundActivePackID) ?? ""
    }

    public func refreshLaunchAtLoginState() {
        let actual = launchAtLoginController.isEnabled()
        guard launchAtLoginEnabled != actual else { return }
        isSyncingLaunchAtLogin = true
        launchAtLoginEnabled = actual
        isSyncingLaunchAtLogin = false
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
            mode: systemMonitorSneakMode(
                from: defaults,
                key: Key.systemMonitorSneakMode,
                fallback: defaultConfiguration.mode
            ),
            left: systemMonitorMetrics(
                from: defaults,
                key: Key.systemMonitorSneakLeftMetrics,
                fallback: defaultConfiguration.leftMetrics
            ),
            right: systemMonitorMetrics(
                from: defaults,
                key: Key.systemMonitorSneakRightMetrics,
                fallback: defaultConfiguration.rightMetrics
            ),
            reactive: systemMonitorMetrics(
                from: defaults,
                key: Key.systemMonitorSneakReactiveMetrics,
                fallback: defaultConfiguration.reactiveMetrics
            )
        )
    }

    private static func systemMonitorSneakMode(
        from defaults: UserDefaults,
        key: String,
        fallback: SystemMonitorSneakMode
    ) -> SystemMonitorSneakMode {
        guard let raw = defaults.string(forKey: key),
              let mode = SystemMonitorSneakMode(rawValue: raw)
        else {
            return fallback
        }
        return mode
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
        defaults.set(configuration.mode.rawValue, forKey: Key.systemMonitorSneakMode)
        defaults.set(configuration.leftMetrics.map(\.rawValue), forKey: Key.systemMonitorSneakLeftMetrics)
        defaults.set(configuration.rightMetrics.map(\.rawValue), forKey: Key.systemMonitorSneakRightMetrics)
        defaults.set(configuration.reactiveMetrics.map(\.rawValue), forKey: Key.systemMonitorSneakReactiveMetrics)
    }

    private static func systemMonitorAlertThresholds(from defaults: UserDefaults) -> SystemMonitorAlertThresholds {
        let fallback = SystemMonitorAlertThresholds.default
        return SystemMonitorAlertThresholds(
            cpuPercent: thresholdValue(
                from: defaults,
                key: Key.systemMonitorAlertCpuPercent,
                fallback: fallback.cpuPercent,
                range: SystemMonitorAlertThresholds.cpuPercentRange
            ),
            memoryPercent: thresholdValue(
                from: defaults,
                key: Key.systemMonitorAlertMemoryPercent,
                fallback: fallback.memoryPercent,
                range: SystemMonitorAlertThresholds.memoryPercentRange
            ),
            temperatureCelsius: thresholdValue(
                from: defaults,
                key: Key.systemMonitorAlertTemperatureCelsius,
                fallback: fallback.temperatureCelsius,
                range: SystemMonitorAlertThresholds.temperatureCelsiusRange
            ),
            batteryPercent: thresholdValue(
                from: defaults,
                key: Key.systemMonitorAlertBatteryPercent,
                fallback: fallback.batteryPercent,
                range: SystemMonitorAlertThresholds.batteryPercentRange
            ),
            diskFreeGB: thresholdValue(
                from: defaults,
                key: Key.systemMonitorAlertDiskFreeGB,
                fallback: fallback.diskFreeGB,
                range: SystemMonitorAlertThresholds.diskFreeGBRange
            ),
            networkMBps: thresholdValue(
                from: defaults,
                key: Key.systemMonitorAlertNetworkMBps,
                fallback: fallback.networkMBps,
                range: SystemMonitorAlertThresholds.networkMBpsRange
            )
        )
    }

    private static func thresholdValue(
        from defaults: UserDefaults,
        key: String,
        fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let raw = defaults.object(forKey: key) as? Double else {
            return fallback
        }
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, raw))
    }

    private func persistSystemMonitorAlertThresholds(_ thresholds: SystemMonitorAlertThresholds) {
        defaults.set(thresholds.cpuPercent, forKey: Key.systemMonitorAlertCpuPercent)
        defaults.set(thresholds.memoryPercent, forKey: Key.systemMonitorAlertMemoryPercent)
        defaults.set(thresholds.temperatureCelsius, forKey: Key.systemMonitorAlertTemperatureCelsius)
        defaults.set(thresholds.batteryPercent, forKey: Key.systemMonitorAlertBatteryPercent)
        defaults.set(thresholds.diskFreeGB, forKey: Key.systemMonitorAlertDiskFreeGB)
        defaults.set(thresholds.networkMBps, forKey: Key.systemMonitorAlertNetworkMBps)
    }
}
