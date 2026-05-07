import SwiftUI

public enum SettingsPluginID: String, CaseIterable, Hashable, Sendable, Identifiable {
    case systemMonitor = "system-monitor"
    case claude
    case codex
    case media = "media-playback"

    public var id: String { rawValue }

    var title: String {
        title(language: .english)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .media:
            return AppStrings.text(.media, language: language)
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .systemMonitor:
            return AppStrings.text(.system, language: language)
        }
    }

    var iconSystemName: String {
        switch self {
        case .media:
            return "music.note"
        case .claude:
            return "sparkles"
        case .codex:
            return "terminal"
        case .systemMonitor:
            return "cpu"
        }
    }

    var brandGlyph: NotchPilotBrandGlyph? {
        switch self {
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .media, .systemMonitor:
            return nil
        }
    }

    var sidebarSubtitle: String {
        sidebarSubtitle(language: .zhHans)
    }

    func sidebarSubtitle(language: AppLanguage) -> String {
        switch self {
        case .media:
            return language == .zhHans ? "媒体播放" : "Media Playback"
        case .claude:
            return language == .zhHans ? "Claude 集成" : "Claude Integration"
        case .codex:
            return AppStrings.text(.connectionStatus, language: language)
        case .systemMonitor:
            return language == .zhHans ? "系统监控" : "System Monitor"
        }
    }
}

struct ClaudeSettingsStatusText: Equatable {
    let value: String

    init(detected: Bool, installed: Bool, needsUpdate: Bool, language: AppLanguage = .zhHans) {
        if detected == false {
            value = AppStrings.connectionStatus(.notDetected, language: language)
        } else if installed == false {
            value = AppStrings.connectionStatus(.notInstalled, language: language)
        } else if needsUpdate {
            value = AppStrings.connectionStatus(.updateAvailable, language: language)
        } else {
            value = AppStrings.connectionStatus(.connected, language: language)
        }
    }
}

struct MediaPluginSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        SettingsPage(title: AppStrings.text(.media, language: store.interfaceLanguage)) {
            SettingsGroupSection(title: AppStrings.text(.playback, language: store.interfaceLanguage)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableMediaPlugin, language: store.interfaceLanguage),
                    detail: AppStrings.text(.enableMediaPluginDetail, language: store.interfaceLanguage),
                    isOn: $store.mediaPlaybackEnabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: AppStrings.text(.showPlaybackPreview, language: store.interfaceLanguage),
                    detail: AppStrings.text(.showPlaybackPreviewDetail, language: store.interfaceLanguage),
                    isEnabled: store.mediaPlaybackEnabled,
                    isOn: $store.mediaPlaybackSneakPreviewEnabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: AppStrings.text(.desktopLyricsCard, language: store.interfaceLanguage),
                    detail: AppStrings.text(.desktopLyricsCardDetail, language: store.interfaceLanguage),
                    isEnabled: store.mediaPlaybackEnabled,
                    isOn: $store.desktopLyricsEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.lyricsStyle, language: store.interfaceLanguage)) {
                SettingsRow(
                    title: AppStrings.text(.highlightColor, language: store.interfaceLanguage),
                    detail: AppStrings.text(.highlightColorDetail, language: store.interfaceLanguage),
                    isEnabled: store.mediaPlaybackEnabled && store.desktopLyricsEnabled
                ) {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(hex: store.desktopLyricsHighlightColorHex) ?? .green },
                            set: { store.desktopLyricsHighlightColorHex = $0.hexString }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .disabled(!store.mediaPlaybackEnabled || !store.desktopLyricsEnabled)
                }

                SettingsRowDivider()

                SettingsRow(
                    title: AppStrings.text(.fontSize, language: store.interfaceLanguage),
                    detail: AppStrings.fontSizeDetail(store.desktopLyricsFontSize, language: store.interfaceLanguage),
                    isEnabled: store.mediaPlaybackEnabled && store.desktopLyricsEnabled
                ) {
                    Slider(value: $store.desktopLyricsFontSize, in: 18...42, step: 2)
                        .frame(width: 170)
                        .disabled(!store.mediaPlaybackEnabled || !store.desktopLyricsEnabled)
                }
            }
        }
    }
}

struct CodexSettingsStatusText: Equatable {
    let value: String

    init(detected: Bool, connection: CodexDesktopConnectionState, language: AppLanguage = .zhHans) {
        if detected == false || connection.status == .notFound {
            value = AppStrings.connectionStatus(.notDetected, language: language)
            return
        }

        switch connection.status {
        case .disconnected:
            value = AppStrings.connectionStatus(.disconnected, language: language)
        case .connecting:
            value = AppStrings.connectionStatus(.connecting, language: language)
        case .connected:
            value = AppStrings.connectionStatus(.connected, language: language)
        case .error:
            value = AppStrings.connectionStatus(.error, language: language)
        case .notFound:
            value = AppStrings.connectionStatus(.notDetected, language: language)
        }
    }
}

public enum SettingsPane: Hashable, Sendable {
    case general
    case plugin(SettingsPluginID)
}

struct SettingsSidebarState: Equatable {
    var selectedPane: SettingsPane

    init(selectedPane: SettingsPane = .general) {
        self.selectedPane = selectedPane
    }

    mutating func selectGeneral() {
        selectedPane = .general
    }

    mutating func selectPlugin(_ plugin: SettingsPluginID) {
        selectedPane = .plugin(plugin)
    }
}

struct ClaudePluginSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    @State private var claudeError: String?
    @State private var isWorking = false

    var body: some View {
        SettingsPage(title: "Claude") {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: store.interfaceLanguage)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableClaudePlugin, language: store.interfaceLanguage),
                    detail: AppStrings.text(.enableClaudePluginDetail, language: store.interfaceLanguage),
                    isOn: $store.claudePluginEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.claudeCode, language: store.interfaceLanguage)) {
                SettingsStatusRow(
                    title: AppStrings.text(.integrationStatus, language: store.interfaceLanguage),
                    value: claudeStatusText.value,
                    valueColor: claudeStatusColor
                )

                SettingsRowDivider()

                SettingsActionRow(
                    title: AppStrings.text(.actions, language: store.interfaceLanguage),
                    detail: claudeActionDetail,
                    buttonTitle: claudeActionTitle,
                    isEnabled: store.claudePluginEnabled && store.claudeCodeDetected && isWorking == false
                ) {
                    claudeAction()
                }
            }

            if let claudeError, claudeError.isEmpty == false {
                SettingsInlineMessage(text: claudeError, color: .red)
            }
        }
        .onAppear {
            refreshInstallationState()
        }
    }

    private var claudeStatusText: ClaudeSettingsStatusText {
        ClaudeSettingsStatusText(
            detected: store.claudeCodeDetected,
            installed: store.claudeHookInstalled,
            needsUpdate: store.claudeHooksNeedUpdate,
            language: store.interfaceLanguage
        )
    }

    private var claudeStatusColor: Color {
        switch claudeStatusText.value {
        case "已连接":
            return .secondary
        case "未检测到", "未安装", "可更新":
            return .secondary
        default:
            return .secondary
        }
    }

    private var claudeActionTitle: String {
        if store.claudeHookInstalled {
            return store.claudeHooksNeedUpdate
                ? AppStrings.text(.updateIntegration, language: store.interfaceLanguage)
                : AppStrings.text(.removeIntegration, language: store.interfaceLanguage)
        }
        return AppStrings.text(.installIntegration, language: store.interfaceLanguage)
    }

    private var claudeActionDetail: String? {
        store.claudeCodeDetected ? nil : AppStrings.text(.claudeCodeMissingDetail, language: store.interfaceLanguage)
    }

    private func claudeAction() {
        if store.claudeHookInstalled, store.claudeHooksNeedUpdate == false {
            uninstallClaude()
        } else {
            installClaude()
        }
    }

    private func installClaude() {
        claudeError = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let bridgePath = try ensureBridgeScript()
            let installer = HookInstaller()
            try installer.installClaudeHooks(bridgeScript: bridgePath)
            store.bridgeScriptPath = bridgePath
            store.synchronizeInstallationState()
        } catch {
            claudeError = error.localizedDescription
        }
    }

    private func uninstallClaude() {
        claudeError = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let bridgePath = store.bridgeScriptPath.isEmpty ? nil : store.bridgeScriptPath
            try HookInstaller().uninstallClaudeHooks(bridgeScript: bridgePath)
            store.synchronizeInstallationState()
        } catch {
            claudeError = error.localizedDescription
        }
    }

    private func ensureBridgeScript() throws -> String {
        if let bundledURL = Bundle.module.url(forResource: "notch-bridge", withExtension: "py") {
            let path = try HookInstaller().installBridgeScript(fromBundle: bundledURL.path)
            store.bridgeScriptPath = path
            return path
        }

        if store.bridgeScriptPath.isEmpty == false,
           FileManager.default.fileExists(atPath: store.bridgeScriptPath) {
            return store.bridgeScriptPath
        }

        let fallbackPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchpilot/notch-bridge.py")
            .path
        guard FileManager.default.fileExists(atPath: fallbackPath) else {
            throw HookInstallError.writeError(
                AppStrings.text(.missingClaudeBridgeScriptError, language: store.interfaceLanguage)
            )
        }

        store.bridgeScriptPath = fallbackPath
        return fallbackPath
    }

    private func refreshInstallationState() {
        store.synchronizeInstallationState()
    }
}

struct CodexPluginSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        SettingsPage(title: "Codex") {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: store.interfaceLanguage)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableCodexPlugin, language: store.interfaceLanguage),
                    detail: AppStrings.text(.enableCodexPluginDetail, language: store.interfaceLanguage),
                    isOn: $store.codexPluginEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.codexDesktop, language: store.interfaceLanguage)) {
                SettingsStatusRow(
                    title: AppStrings.text(.connectionStatus, language: store.interfaceLanguage),
                    value: codexStatusText.value,
                    valueColor: codexStatusColor
                )
            }

            if let message = store.codexDesktopConnection.message, message.isEmpty == false {
                SettingsInlineMessage(
                    text: message,
                    color: store.codexDesktopConnection.status == .error ? .red : .secondary
                )
            }
        }
        .onAppear {
            store.synchronizeInstallationState()
        }
    }

    private var codexStatusText: CodexSettingsStatusText {
        CodexSettingsStatusText(
            detected: store.codexDetected,
            connection: store.codexDesktopConnection,
            language: store.interfaceLanguage
        )
    }

    private var codexStatusColor: Color {
        store.codexDesktopConnection.status == .error ? .red : .secondary
    }
}

struct SystemMonitorPluginSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        SettingsPage(title: AppStrings.text(.system, language: store.interfaceLanguage)) {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: store.interfaceLanguage)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableSystemMonitorPlugin, language: store.interfaceLanguage),
                    detail: AppStrings.text(.enableSystemMonitorPluginDetail, language: store.interfaceLanguage),
                    isOn: $store.systemMonitorEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.preview, language: store.interfaceLanguage)) {
                SettingsToggleRow(
                    title: AppStrings.text(.showSystemMonitorPreview, language: store.interfaceLanguage),
                    isEnabled: store.systemMonitorEnabled,
                    isOn: $store.systemMonitorSneakPreviewEnabled
                )

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.sneakPreviewMode, language: store.interfaceLanguage),
                    detail: AppStrings.text(.sneakPreviewModeDetail, language: store.interfaceLanguage),
                    selection: modeBinding,
                    isEnabled: store.systemMonitorEnabled && store.systemMonitorSneakPreviewEnabled
                ) {
                    modeOptions
                }
            }

            SettingsGroupSection(
                title: AppStrings.text(.pinnedSlots, language: store.interfaceLanguage),
                footer: AppStrings.text(.pinnedSlotsFooter, language: store.interfaceLanguage)
            ) {
                SettingsPickerRow(
                    title: AppStrings.text(.leftSlot1, language: store.interfaceLanguage),
                    selection: metricBinding(side: .left, index: 0),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.leftSlot2, language: store.interfaceLanguage),
                    selection: metricBinding(side: .left, index: 1),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.rightSlot1, language: store.interfaceLanguage),
                    selection: metricBinding(side: .right, index: 0),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.rightSlot2, language: store.interfaceLanguage),
                    selection: metricBinding(side: .right, index: 1),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }
            }

            SettingsGroupSection(
                title: AppStrings.text(.reactiveMetrics, language: store.interfaceLanguage),
                footer: AppStrings.text(.reactiveMetricsFooter, language: store.interfaceLanguage)
            ) {
                ForEach(Array(SystemMonitorMetric.allCases.enumerated()), id: \.element) { entry in
                    let metric = entry.element
                    if entry.offset > 0 {
                        SettingsRowDivider()
                    }
                    SettingsToggleRow(
                        title: metric.settingsTitle(language: store.interfaceLanguage),
                        isEnabled: areReactiveMetricsActive && isMetricPinned(metric) == false,
                        isOn: reactiveBinding(for: metric)
                    )
                }
            }

            SettingsGroupSection(
                title: AppStrings.text(.reactiveThresholds, language: store.interfaceLanguage),
                footer: AppStrings.text(.reactiveThresholdsFooter, language: store.interfaceLanguage)
            ) {
                ForEach(Array(SystemMonitorMetric.allCases.enumerated()), id: \.element) { entry in
                    let metric = entry.element
                    if entry.offset > 0 {
                        SettingsRowDivider()
                    }
                    thresholdRow(for: metric)
                }
            }
        }
    }

    @ViewBuilder
    private func thresholdRow(for metric: SystemMonitorMetric) -> some View {
        let value = store.systemMonitorAlertThresholds.value(for: metric)
        let detail = AppStrings.systemMonitorThresholdDetail(
            metric: metric,
            value: value,
            language: store.interfaceLanguage
        )
        SettingsRow(
            title: thresholdRowTitle(for: metric),
            detail: detail,
            isEnabled: areReactiveMetricsActive
        ) {
            HStack(spacing: 10) {
                Text(AppStrings.systemMonitorThresholdValueText(metric: metric, value: value))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)

                Stepper(
                    "",
                    value: thresholdBinding(for: metric),
                    in: SystemMonitorAlertThresholds.range(for: metric),
                    step: SystemMonitorAlertThresholds.step(for: metric)
                )
                .labelsHidden()
                .disabled(areReactiveMetricsActive == false)
            }
        }
    }

    private func thresholdRowTitle(for metric: SystemMonitorMetric) -> String {
        switch metric {
        case .cpu:
            return AppStrings.text(.cpuThresholdTitle, language: store.interfaceLanguage)
        case .memory:
            return AppStrings.text(.memoryThresholdTitle, language: store.interfaceLanguage)
        case .temperature:
            return AppStrings.text(.temperatureThresholdTitle, language: store.interfaceLanguage)
        case .battery:
            return AppStrings.text(.batteryThresholdTitle, language: store.interfaceLanguage)
        case .disk:
            return AppStrings.text(.diskThresholdTitle, language: store.interfaceLanguage)
        case .network:
            return AppStrings.text(.networkThresholdTitle, language: store.interfaceLanguage)
        }
    }

    private func thresholdBinding(for metric: SystemMonitorMetric) -> Binding<Double> {
        Binding(
            get: { store.systemMonitorAlertThresholds.value(for: metric) },
            set: { newValue in
                store.systemMonitorAlertThresholds = store.systemMonitorAlertThresholds
                    .setting(newValue, for: metric)
            }
        )
    }

    private var arePinnedSlotsActive: Bool {
        store.systemMonitorEnabled
            && store.systemMonitorSneakPreviewEnabled
            && store.systemMonitorSneakConfiguration.mode != .ambient
    }

    private var areReactiveMetricsActive: Bool {
        store.systemMonitorEnabled
            && store.systemMonitorSneakPreviewEnabled
            && store.systemMonitorSneakConfiguration.mode != .alwaysOn
    }

    private var modeBinding: Binding<SystemMonitorSneakMode> {
        Binding(
            get: { store.systemMonitorSneakConfiguration.mode },
            set: { newMode in
                let configuration = store.systemMonitorSneakConfiguration
                store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
                    mode: newMode,
                    left: configuration.leftMetrics,
                    right: configuration.rightMetrics,
                    reactive: configuration.reactiveMetrics
                )
            }
        )
    }

    @ViewBuilder
    private var modeOptions: some View {
        Text(AppStrings.text(.sneakPreviewModeAlwaysOn, language: store.interfaceLanguage))
            .tag(SystemMonitorSneakMode.alwaysOn)
        Text(AppStrings.text(.sneakPreviewModePinnedReactive, language: store.interfaceLanguage))
            .tag(SystemMonitorSneakMode.pinnedReactive)
        Text(AppStrings.text(.sneakPreviewModeAmbient, language: store.interfaceLanguage))
            .tag(SystemMonitorSneakMode.ambient)
    }

    @ViewBuilder
    private var metricOptions: some View {
        Text(AppStrings.text(.hidden, language: store.interfaceLanguage))
            .tag(SystemMonitorMetric?.none)

        ForEach(SystemMonitorMetric.allCases, id: \.self) { metric in
            Text(metric.settingsTitle(language: store.interfaceLanguage))
                .tag(Optional(metric))
        }
    }

    private func metricBinding(side: SystemMonitorSneakSide, index: Int) -> Binding<SystemMonitorMetric?> {
        Binding(
            get: {
                metric(side: side, index: index)
            },
            set: { metric in
                updateMetric(metric, side: side, index: index)
            }
        )
    }

    private func metric(side: SystemMonitorSneakSide, index: Int) -> SystemMonitorMetric? {
        let metrics = metrics(side: side)
        guard metrics.indices.contains(index) else {
            return nil
        }
        return metrics[index]
    }

    private func metrics(side: SystemMonitorSneakSide) -> [SystemMonitorMetric] {
        switch side {
        case .left:
            return store.systemMonitorSneakConfiguration.leftMetrics
        case .right:
            return store.systemMonitorSneakConfiguration.rightMetrics
        }
    }

    private func updateMetric(_ metric: SystemMonitorMetric?, side: SystemMonitorSneakSide, index: Int) {
        let configuration = store.systemMonitorSneakConfiguration
        switch side {
        case .left:
            store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
                mode: configuration.mode,
                left: updatedMetrics(configuration.leftMetrics, setting: metric, at: index),
                right: configuration.rightMetrics,
                reactive: configuration.reactiveMetrics
            )
        case .right:
            store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
                mode: configuration.mode,
                left: configuration.leftMetrics,
                right: updatedMetrics(configuration.rightMetrics, setting: metric, at: index),
                reactive: configuration.reactiveMetrics
            )
        }
    }

    private func updatedMetrics(
        _ metrics: [SystemMonitorMetric],
        setting metric: SystemMonitorMetric?,
        at index: Int
    ) -> [SystemMonitorMetric] {
        SystemMonitorSneakSlotEditor.metrics(
            byUpdating: metrics,
            setting: metric,
            at: index
        )
    }

    private func isMetricPinned(_ metric: SystemMonitorMetric) -> Bool {
        let configuration = store.systemMonitorSneakConfiguration
        return configuration.leftMetrics.contains(metric)
            || configuration.rightMetrics.contains(metric)
    }

    private func reactiveBinding(for metric: SystemMonitorMetric) -> Binding<Bool> {
        Binding(
            get: {
                store.systemMonitorSneakConfiguration.reactiveMetrics.contains(metric)
            },
            set: { isOn in
                let configuration = store.systemMonitorSneakConfiguration
                var reactive = configuration.reactiveMetrics
                if isOn {
                    if reactive.contains(metric) == false {
                        reactive.append(metric)
                    }
                } else {
                    reactive.removeAll { $0 == metric }
                }
                store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
                    mode: configuration.mode,
                    left: configuration.leftMetrics,
                    right: configuration.rightMetrics,
                    reactive: reactive
                )
            }
        )
    }
}

private enum SystemMonitorSneakSide {
    case left
    case right
}

private extension SystemMonitorMetric {
    func settingsTitle(language: AppLanguage) -> String {
        AppStrings.systemMonitorMetricTitle(self, language: language)
    }
}
