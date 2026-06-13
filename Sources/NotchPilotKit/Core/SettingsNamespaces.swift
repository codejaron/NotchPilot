import Combine
import Foundation

@MainActor
class SettingsNamespace: ObservableObject {
    unowned let store: SettingsStore
    private var storeCancellable: AnyCancellable?

    init(store: SettingsStore) {
        self.store = store
        self.storeCancellable = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
}

@MainActor
final class SettingsGeneralNamespace: SettingsNamespace {
    var interfaceLanguage: AppLanguage {
        get { store.interfaceLanguage }
        set { store.interfaceLanguage = newValue }
    }

    var launchAtLoginEnabled: Bool {
        get { store.launchAtLoginEnabled }
        set { store.launchAtLoginEnabled = newValue }
    }

    var activitySneakPreviewsHidden: Bool {
        get { store.activitySneakPreviewsHidden }
        set { store.activitySneakPreviewsHidden = newValue }
    }

    func refreshLaunchAtLoginState() {
        store.refreshLaunchAtLoginState()
    }
}

@MainActor
final class SettingsBridgeNamespace: SettingsNamespace {
    var autoStartSocket: Bool {
        get { store.autoStartSocket }
        set { store.autoStartSocket = newValue }
    }

    var bridgeScriptPath: String {
        get { store.bridgeScriptPath }
        set { store.bridgeScriptPath = newValue }
    }

    var claudeHookInstalled: Bool {
        store.claudeHookInstalled
    }

    var claudeHooksNeedUpdate: Bool {
        store.claudeHooksNeedUpdate
    }

    func synchronizeInstallationState() {
        store.synchronizeInstallationState()
    }
}

@MainActor
final class SettingsAINamespace: SettingsNamespace {
    var approvalSneakNotificationsEnabled: Bool {
        get { store.approvalSneakNotificationsEnabled }
        set { store.approvalSneakNotificationsEnabled = newValue }
    }

    var activitySneakPreviewsHidden: Bool {
        get { store.activitySneakPreviewsHidden }
        set { store.activitySneakPreviewsHidden = newValue }
    }

    var claudePluginEnabled: Bool {
        get { store.claudePluginEnabled }
        set { store.claudePluginEnabled = newValue }
    }

    var codexPluginEnabled: Bool {
        get { store.codexPluginEnabled }
        set { store.codexPluginEnabled = newValue }
    }

    var devinPluginEnabled: Bool {
        get { store.devinPluginEnabled }
        set { store.devinPluginEnabled = newValue }
    }

    var claudeCodeDetected: Bool {
        store.claudeCodeDetected
    }

    var codexDetected: Bool {
        store.codexDetected
    }

    var claudeHookInstalled: Bool {
        store.claudeHookInstalled
    }

    var claudeHooksNeedUpdate: Bool {
        store.claudeHooksNeedUpdate
    }

    var bridgeScriptPath: String {
        get { store.bridgeScriptPath }
        set { store.bridgeScriptPath = newValue }
    }

    func synchronizeInstallationState() {
        store.synchronizeInstallationState()
    }
}

@MainActor
final class SettingsMediaNamespace: SettingsNamespace {
    var mediaPlaybackEnabled: Bool {
        get { store.mediaPlaybackEnabled }
        set { store.mediaPlaybackEnabled = newValue }
    }

    var mediaPlaybackSneakPreviewEnabled: Bool {
        get { store.mediaPlaybackSneakPreviewEnabled }
        set { store.mediaPlaybackSneakPreviewEnabled = newValue }
    }
}

@MainActor
final class SettingsLyricsNamespace: SettingsNamespace {
    var desktopLyricsEnabled: Bool {
        get { store.desktopLyricsEnabled }
        set { store.desktopLyricsEnabled = newValue }
    }

    var desktopLyricsHighlightColorHex: String {
        get { store.desktopLyricsHighlightColorHex }
        set { store.desktopLyricsHighlightColorHex = newValue }
    }

    var desktopLyricsFontSize: Double {
        get { store.desktopLyricsFontSize }
        set { store.desktopLyricsFontSize = newValue }
    }

    var desktopLyricsAllowInsecureSources: Bool {
        get { store.desktopLyricsAllowInsecureSources }
        set { store.desktopLyricsAllowInsecureSources = newValue }
    }
}

@MainActor
final class SettingsSystemMonitorNamespace: SettingsNamespace {
    var systemMonitorEnabled: Bool {
        get { store.systemMonitorEnabled }
        set { store.systemMonitorEnabled = newValue }
    }

    var systemMonitorSneakPreviewEnabled: Bool {
        get { store.systemMonitorSneakPreviewEnabled }
        set { store.systemMonitorSneakPreviewEnabled = newValue }
    }

    var systemMonitorSneakConfiguration: SystemMonitorSneakConfiguration {
        get { store.systemMonitorSneakConfiguration }
        set { store.systemMonitorSneakConfiguration = newValue }
    }

    var systemMonitorAlertThresholds: SystemMonitorAlertThresholds {
        get { store.systemMonitorAlertThresholds }
        set { store.systemMonitorAlertThresholds = newValue }
    }
}

@MainActor
final class SettingsSoundNamespace: SettingsNamespace {
    var soundEnabled: Bool {
        get { store.soundEnabled }
        set { store.soundEnabled = newValue }
    }

    var soundTaskCompleteVolume: Double {
        get { store.soundTaskCompleteVolume }
        set { store.soundTaskCompleteVolume = newValue }
    }

    var soundInputRequiredVolume: Double {
        get { store.soundInputRequiredVolume }
        set { store.soundInputRequiredVolume = newValue }
    }

    var soundActivePackID: String {
        get { store.soundActivePackID }
        set { store.soundActivePackID = newValue }
    }
}
