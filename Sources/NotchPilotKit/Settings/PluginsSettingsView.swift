import AppKit
import SwiftUI

public enum SettingsPluginID: String, CaseIterable, Hashable, Sendable, Identifiable {
    case systemMonitor = "system-monitor"
    case claude
    case devin
    case codex
    case media = "media-playback"
    case notes

    public var id: String { rawValue }

    var title: String {
        title(language: .english)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .media:
            return AppStrings.text(.media, language: language)
        case .notes:
            return AppStrings.text(.notes, language: language)
        case .claude:
            return "Claude"
        case .devin:
            return "Devin"
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
        case .notes:
            return "note.text"
        case .claude:
            return "sparkles"
        case .devin:
            return "wind"
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
        case .devin:
            return .devin
        case .codex:
            return .codex
        case .media, .notes, .systemMonitor:
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
        case .notes:
            return AppStrings.text(.notesSidebarSubtitle, language: language)
        case .claude:
            return language == .zhHans ? "Claude 集成" : "Claude Integration"
        case .devin:
            return AppStrings.text(.devinIntegration, language: language)
        case .codex:
            return AppStrings.text(.connectionStatus, language: language)
        case .systemMonitor:
            return language == .zhHans ? "系统监控" : "System Monitor"
        }
    }
}

struct NotesPluginSettingsView: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject private var notesSettings = SettingsStore.shared.notes
    private let store = ScratchpadStore()

    @State private var isMigrationPromptPresented = false
    @State private var migrationMessage: String?

    var body: some View {
        SettingsPage(title: AppStrings.text(.notes, language: language)) {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableNotesPlugin, language: language),
                    detail: AppStrings.text(.enableNotesPluginDetail, language: language),
                    isOn: $notesSettings.notesEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.notesFiles, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.copyDroppedFilesToScratchpad, language: language),
                    detail: AppStrings.text(.copyDroppedFilesToScratchpadDetail, language: language),
                    isEnabled: notesSettings.notesEnabled,
                    isOn: copyDraggedFilesBinding
                )

                SettingsRowDivider()

                SettingsActionRow(
                    title: AppStrings.text(.scratchpadRoot, language: language),
                    detail: store.rootURL.path,
                    buttonTitle: AppStrings.text(.open, language: language),
                    isEnabled: notesSettings.notesEnabled
                ) {
                    try? FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([store.rootURL])
                }
            }

            if let migrationMessage {
                SettingsInlineMessage(text: migrationMessage, color: .secondary)
            }
        }
        .confirmationDialog(
            AppStrings.text(.migrateExistingExternalFiles, language: language),
            isPresented: $isMigrationPromptPresented
        ) {
            Button(AppStrings.text(.migrateNow, language: language)) {
                migrateExistingExternalLinks()
            }
            Button(AppStrings.text(.skip, language: language), role: .cancel) {}
        }
    }

    private var copyDraggedFilesBinding: Binding<Bool> {
        Binding(
            get: { notesSettings.notesCopyDraggedFilesToScratchpad },
            set: { newValue in
                let wasEnabled = notesSettings.notesCopyDraggedFilesToScratchpad
                notesSettings.notesCopyDraggedFilesToScratchpad = newValue
                if newValue, wasEnabled == false {
                    isMigrationPromptPresented = true
                }
            }
        )
    }

    private func migrateExistingExternalLinks() {
        do {
            let result = try store.migrateExternalMarkdownLinks()
            migrationMessage = AppStrings.notesMigrationResult(
                migratedCount: result.migratedCount,
                failedCount: result.failedCount,
                language: language
            )
        } catch {
            migrationMessage = error.localizedDescription
        }
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
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
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject private var mediaSettings = SettingsStore.shared.media
    @ObservedObject private var lyricsSettings = SettingsStore.shared.lyrics

    var body: some View {
        SettingsPage(title: AppStrings.text(.media, language: language)) {
            SettingsGroupSection(title: AppStrings.text(.playback, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableMediaPlugin, language: language),
                    detail: AppStrings.text(.enableMediaPluginDetail, language: language),
                    isOn: $mediaSettings.mediaPlaybackEnabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: AppStrings.text(.showPlaybackPreview, language: language),
                    detail: AppStrings.text(.showPlaybackPreviewDetail, language: language),
                    isEnabled: mediaSettings.mediaPlaybackEnabled,
                    isOn: $mediaSettings.mediaPlaybackSneakPreviewEnabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: AppStrings.text(.desktopLyricsCard, language: language),
                    detail: AppStrings.text(.desktopLyricsCardDetail, language: language),
                    isEnabled: mediaSettings.mediaPlaybackEnabled,
                    isOn: $lyricsSettings.desktopLyricsEnabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: AppStrings.text(.blockHTTPLyricsSources, language: language),
                    detail: AppStrings.text(.blockHTTPLyricsSourcesDetail, language: language),
                    isEnabled: mediaSettings.mediaPlaybackEnabled && lyricsSettings.desktopLyricsEnabled,
                    isOn: Binding(
                        get: { lyricsSettings.desktopLyricsAllowInsecureSources == false },
                        set: { lyricsSettings.desktopLyricsAllowInsecureSources = $0 == false }
                    )
                )
            }

            SettingsGroupSection(title: AppStrings.text(.lyricsStyle, language: language)) {
                SettingsRow(
                    title: AppStrings.text(.highlightColor, language: language),
                    detail: AppStrings.text(.highlightColorDetail, language: language),
                    isEnabled: mediaSettings.mediaPlaybackEnabled && lyricsSettings.desktopLyricsEnabled
                ) {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(hex: lyricsSettings.desktopLyricsHighlightColorHex) ?? .green },
                            set: { lyricsSettings.desktopLyricsHighlightColorHex = $0.hexString }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .disabled(!mediaSettings.mediaPlaybackEnabled || !lyricsSettings.desktopLyricsEnabled)
                }

                SettingsRowDivider()

                SettingsRow(
                    title: AppStrings.text(.fontSize, language: language),
                    detail: AppStrings.fontSizeDetail(lyricsSettings.desktopLyricsFontSize, language: language),
                    isEnabled: mediaSettings.mediaPlaybackEnabled && lyricsSettings.desktopLyricsEnabled
                ) {
                    Slider(value: $lyricsSettings.desktopLyricsFontSize, in: 18...42, step: 2)
                        .frame(width: 170)
                        .disabled(!mediaSettings.mediaPlaybackEnabled || !lyricsSettings.desktopLyricsEnabled)
                }
            }
        }
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
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
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject private var aiSettings = SettingsStore.shared.ai

    @State private var claudeError: String?
    @State private var isWorking = false

    var body: some View {
        SettingsPage(title: "Claude") {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableClaudePlugin, language: language),
                    detail: AppStrings.text(.enableClaudePluginDetail, language: language),
                    isOn: $aiSettings.claudePluginEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.claudeCode, language: language)) {
                SettingsStatusRow(
                    title: AppStrings.text(.integrationStatus, language: language),
                    value: claudeStatusText.value,
                    valueColor: claudeStatusColor
                )

                SettingsRowDivider()

                SettingsActionRow(
                    title: AppStrings.text(.actions, language: language),
                    detail: claudeActionDetail,
                    buttonTitle: claudeActionTitle,
                    isEnabled: aiSettings.claudePluginEnabled && aiSettings.claudeCodeDetected && isWorking == false
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
            detected: aiSettings.claudeCodeDetected,
            installed: aiSettings.claudeHookInstalled,
            needsUpdate: aiSettings.claudeHooksNeedUpdate,
            language: language
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
        if aiSettings.claudeHookInstalled {
            return aiSettings.claudeHooksNeedUpdate
                ? AppStrings.text(.updateIntegration, language: language)
                : AppStrings.text(.removeIntegration, language: language)
        }
        return AppStrings.text(.installIntegration, language: language)
    }

    private var claudeActionDetail: String? {
        aiSettings.claudeCodeDetected ? nil : AppStrings.text(.claudeCodeMissingDetail, language: language)
    }

    private func claudeAction() {
        if aiSettings.claudeHookInstalled, aiSettings.claudeHooksNeedUpdate == false {
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
            aiSettings.bridgeScriptPath = bridgePath
            aiSettings.synchronizeInstallationState()
        } catch {
            claudeError = error.localizedDescription
        }
    }

    private func uninstallClaude() {
        claudeError = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let bridgePath = aiSettings.bridgeScriptPath.isEmpty ? nil : aiSettings.bridgeScriptPath
            try HookInstaller().uninstallClaudeHooks(bridgeScript: bridgePath)
            aiSettings.synchronizeInstallationState()
        } catch {
            claudeError = error.localizedDescription
        }
    }

    private func ensureBridgeScript() throws -> String {
        if let bundledURL = Bundle.module.url(forResource: "notch-bridge", withExtension: "py") {
            let path = try HookInstaller().installBridgeScript(fromBundle: bundledURL.path)
            aiSettings.bridgeScriptPath = path
            return path
        }

        if aiSettings.bridgeScriptPath.isEmpty == false,
           FileManager.default.fileExists(atPath: aiSettings.bridgeScriptPath) {
            return aiSettings.bridgeScriptPath
        }

        let fallbackPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchpilot/notch-bridge.py")
            .path
        guard FileManager.default.fileExists(atPath: fallbackPath) else {
            throw HookInstallError.writeError(
                AppStrings.text(.missingClaudeBridgeScriptError, language: language)
            )
        }

        aiSettings.bridgeScriptPath = fallbackPath
        return fallbackPath
    }

    private func refreshInstallationState() {
        aiSettings.synchronizeInstallationState()
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }
}

/// Devin Local piggybacks on Claude Code's hook configuration (it auto-imports
/// `~/.claude/settings.json`), so this page intentionally does *not* expose its
/// own install/uninstall flow. The page is just a switch for whether NotchPilot
/// should surface Devin sessions, plus a hint pointing users at the Claude tab
/// when the underlying integration is missing or stale.
struct DevinPluginSettingsView: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject private var aiSettings = SettingsStore.shared.ai

    var body: some View {
        SettingsPage(title: "Devin") {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableDevinPlugin, language: language),
                    detail: AppStrings.text(.enableDevinPluginDetail, language: language),
                    isOn: $aiSettings.devinPluginEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.devinIntegration, language: language)) {
                SettingsStatusRow(
                    title: AppStrings.text(.integrationStatus, language: language),
                    value: devinStatusText,
                    valueColor: .secondary
                )
            }

            SettingsInlineMessage(
                text: AppStrings.text(.devinIntegrationDetail, language: language),
                color: .secondary
            )
        }
        .onAppear {
            aiSettings.synchronizeInstallationState()
        }
    }

    private var devinStatusText: String {
        // Devin's "integration" is really the Claude hook bridge — surface
        // whichever underlying state is most actionable for the user.
        if aiSettings.claudeHookInstalled == false {
            return AppStrings.connectionStatus(.notInstalled, language: language)
        }
        if aiSettings.claudeHooksNeedUpdate {
            return AppStrings.connectionStatus(.updateAvailable, language: language)
        }
        return AppStrings.connectionStatus(.connected, language: language)
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }
}

struct CodexPluginSettingsView: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject private var aiSettings = SettingsStore.shared.ai
    @ObservedObject private var connectionStore = CodexDesktopConnectionStore.shared

    var body: some View {
        SettingsPage(title: "Codex") {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableCodexPlugin, language: language),
                    detail: AppStrings.text(.enableCodexPluginDetail, language: language),
                    isOn: $aiSettings.codexPluginEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.codexDesktop, language: language)) {
                SettingsStatusRow(
                    title: AppStrings.text(.connectionStatus, language: language),
                    value: codexStatusText.value,
                    valueColor: codexStatusColor
                )
            }

            if let message = connectionStore.connection.message, message.isEmpty == false {
                SettingsInlineMessage(
                    text: message,
                    color: connectionStore.connection.status == .error ? .red : .secondary
                )
            }
        }
        .onAppear {
            aiSettings.synchronizeInstallationState()
            connectionStore.synchronizeInstallationState(isDetected: aiSettings.codexDetected)
        }
    }

    private var codexStatusText: CodexSettingsStatusText {
        CodexSettingsStatusText(
            detected: aiSettings.codexDetected,
            connection: connectionStore.connection,
            language: language
        )
    }

    private var codexStatusColor: Color {
        connectionStore.connection.status == .error ? .red : .secondary
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }
}

struct SystemMonitorPluginSettingsView: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject private var systemSettings = SettingsStore.shared.systemMonitor

    var body: some View {
        SettingsPage(title: AppStrings.text(.system, language: language)) {
            SettingsGroupSection(title: AppStrings.text(.plugin, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableSystemMonitorPlugin, language: language),
                    detail: AppStrings.text(.enableSystemMonitorPluginDetail, language: language),
                    isOn: $systemSettings.systemMonitorEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.preview, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.showSystemMonitorPreview, language: language),
                    isEnabled: systemSettings.systemMonitorEnabled,
                    isOn: $systemSettings.systemMonitorSneakPreviewEnabled
                )

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.sneakPreviewMode, language: language),
                    detail: AppStrings.text(.sneakPreviewModeDetail, language: language),
                    selection: modeBinding,
                    isEnabled: systemSettings.systemMonitorEnabled && systemSettings.systemMonitorSneakPreviewEnabled
                ) {
                    modeOptions
                }
            }

            SettingsGroupSection(
                title: AppStrings.text(.pinnedSlots, language: language),
                footer: AppStrings.text(.pinnedSlotsFooter, language: language)
            ) {
                SettingsPickerRow(
                    title: AppStrings.text(.leftSlot1, language: language),
                    selection: metricBinding(side: .left, index: 0),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.leftSlot2, language: language),
                    selection: metricBinding(side: .left, index: 1),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.rightSlot1, language: language),
                    selection: metricBinding(side: .right, index: 0),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: AppStrings.text(.rightSlot2, language: language),
                    selection: metricBinding(side: .right, index: 1),
                    isEnabled: arePinnedSlotsActive
                ) {
                    metricOptions
                }
            }

            SettingsGroupSection(
                title: AppStrings.text(.reactiveMetrics, language: language),
                footer: AppStrings.text(.reactiveMetricsFooter, language: language)
            ) {
                ForEach(Array(SystemMonitorMetric.allCases.enumerated()), id: \.element) { entry in
                    let metric = entry.element
                    if entry.offset > 0 {
                        SettingsRowDivider()
                    }
                    SettingsToggleRow(
                        title: metric.settingsTitle(language: language),
                        isEnabled: SystemMonitorSettingsAvailability.reactiveMetricToggleActive(
                            systemMonitorEnabled: systemSettings.systemMonitorEnabled,
                            sneakPreviewEnabled: systemSettings.systemMonitorSneakPreviewEnabled,
                            mode: systemSettings.systemMonitorSneakConfiguration.mode,
                            isMetricPinned: isMetricPinned(metric)
                        ),
                        isOn: reactiveBinding(for: metric)
                    )
                }
            }

            SettingsGroupSection(
                title: AppStrings.text(.reactiveThresholds, language: language),
                footer: AppStrings.text(.reactiveThresholdsFooter, language: language)
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
        let value = systemSettings.systemMonitorAlertThresholds.value(for: metric)
        let detail = AppStrings.systemMonitorThresholdDetail(
            metric: metric,
            value: value,
            language: language
        )
        SettingsRow(
            title: thresholdRowTitle(for: metric),
            detail: detail,
            isEnabled: areAlertThresholdsActive
        ) {
            HStack(spacing: 8) {
                Slider(
                    value: thresholdBinding(for: metric),
                    in: SystemMonitorAlertThresholds.range(for: metric)
                )
                .frame(width: 170)

                HStack(spacing: 4) {
                    TextField(
                        "",
                        value: thresholdBinding(for: metric),
                        format: .number.precision(.fractionLength(0))
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(width: 58)
                    .accessibilityLabel(thresholdRowTitle(for: metric))

                    Text(thresholdUnitText(for: metric))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: thresholdUnitWidth(for: metric), alignment: .leading)
                }
            }
            .disabled(areAlertThresholdsActive == false)
        }
    }

    private func thresholdRowTitle(for metric: SystemMonitorMetric) -> String {
        switch metric {
        case .cpu:
            return AppStrings.text(.cpuThresholdTitle, language: language)
        case .memory:
            return AppStrings.text(.memoryThresholdTitle, language: language)
        case .temperature:
            return AppStrings.text(.temperatureThresholdTitle, language: language)
        case .battery:
            return AppStrings.text(.batteryThresholdTitle, language: language)
        case .disk:
            return AppStrings.text(.diskThresholdTitle, language: language)
        case .network:
            return AppStrings.text(.networkThresholdTitle, language: language)
        }
    }

    private func thresholdBinding(for metric: SystemMonitorMetric) -> Binding<Double> {
        Binding(
            get: { systemSettings.systemMonitorAlertThresholds.value(for: metric) },
            set: { newValue in
                systemSettings.systemMonitorAlertThresholds = systemSettings.systemMonitorAlertThresholds
                    .setting(newValue.rounded(), for: metric)
            }
        )
    }

    private func thresholdUnitText(for metric: SystemMonitorMetric) -> String {
        switch metric {
        case .cpu, .memory, .battery:
            return "%"
        case .temperature:
            return "°C"
        case .disk:
            return "GB"
        case .network:
            return "MB/s"
        }
    }

    private func thresholdUnitWidth(for metric: SystemMonitorMetric) -> CGFloat {
        metric == .network ? 34 : 22
    }

    private var arePinnedSlotsActive: Bool {
        SystemMonitorSettingsAvailability.pinnedSlotsActive(
            systemMonitorEnabled: systemSettings.systemMonitorEnabled,
            sneakPreviewEnabled: systemSettings.systemMonitorSneakPreviewEnabled,
            mode: systemSettings.systemMonitorSneakConfiguration.mode
        )
    }

    private var areAlertThresholdsActive: Bool {
        SystemMonitorSettingsAvailability.alertThresholdsActive(
            systemMonitorEnabled: systemSettings.systemMonitorEnabled,
            sneakPreviewEnabled: systemSettings.systemMonitorSneakPreviewEnabled
        )
    }

    private var modeBinding: Binding<SystemMonitorSneakMode> {
        Binding(
            get: { systemSettings.systemMonitorSneakConfiguration.mode },
            set: { newMode in
                let configuration = systemSettings.systemMonitorSneakConfiguration
                systemSettings.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
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
        Text(AppStrings.text(.sneakPreviewModeAlwaysOn, language: language))
            .tag(SystemMonitorSneakMode.alwaysOn)
        Text(AppStrings.text(.sneakPreviewModePinnedReactive, language: language))
            .tag(SystemMonitorSneakMode.pinnedReactive)
        Text(AppStrings.text(.sneakPreviewModeAmbient, language: language))
            .tag(SystemMonitorSneakMode.ambient)
    }

    @ViewBuilder
    private var metricOptions: some View {
        Text(AppStrings.text(.hidden, language: language))
            .tag(SystemMonitorMetric?.none)

        ForEach(SystemMonitorMetric.allCases, id: \.self) { metric in
            Text(metric.settingsTitle(language: language))
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
            return systemSettings.systemMonitorSneakConfiguration.leftMetrics
        case .right:
            return systemSettings.systemMonitorSneakConfiguration.rightMetrics
        }
    }

    private func updateMetric(_ metric: SystemMonitorMetric?, side: SystemMonitorSneakSide, index: Int) {
        let configuration = systemSettings.systemMonitorSneakConfiguration
        switch side {
        case .left:
            systemSettings.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
                mode: configuration.mode,
                left: updatedMetrics(configuration.leftMetrics, setting: metric, at: index),
                right: configuration.rightMetrics,
                reactive: configuration.reactiveMetrics
            )
        case .right:
            systemSettings.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
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
        let configuration = systemSettings.systemMonitorSneakConfiguration
        return configuration.leftMetrics.contains(metric)
            || configuration.rightMetrics.contains(metric)
    }

    private func reactiveBinding(for metric: SystemMonitorMetric) -> Binding<Bool> {
        Binding(
            get: {
                let configuration = systemSettings.systemMonitorSneakConfiguration
                return SystemMonitorSettingsAvailability.reactiveMetricToggleValue(
                    storedValue: configuration.reactiveMetrics.contains(metric),
                    mode: configuration.mode,
                    isMetricPinned: isMetricPinned(metric)
                )
            },
            set: { isOn in
                let configuration = systemSettings.systemMonitorSneakConfiguration
                var reactive = configuration.reactiveMetrics
                if isOn {
                    if reactive.contains(metric) == false {
                        reactive.append(metric)
                    }
                } else {
                    reactive.removeAll { $0 == metric }
                }
                systemSettings.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
                    mode: configuration.mode,
                    left: configuration.leftMetrics,
                    right: configuration.rightMetrics,
                    reactive: reactive
                )
            }
        )
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }
}

private enum SystemMonitorSneakSide {
    case left
    case right
}

enum SystemMonitorSettingsAvailability {
    static func pinnedSlotsActive(
        systemMonitorEnabled: Bool,
        sneakPreviewEnabled: Bool,
        mode: SystemMonitorSneakMode
    ) -> Bool {
        systemMonitorEnabled
            && sneakPreviewEnabled
            && mode != .ambient
    }

    static func reactiveMetricsActive(
        systemMonitorEnabled: Bool,
        sneakPreviewEnabled: Bool,
        mode: SystemMonitorSneakMode
    ) -> Bool {
        systemMonitorEnabled && sneakPreviewEnabled
    }

    static func reactiveMetricToggleActive(
        systemMonitorEnabled: Bool,
        sneakPreviewEnabled: Bool,
        mode: SystemMonitorSneakMode,
        isMetricPinned: Bool
    ) -> Bool {
        guard systemMonitorEnabled && sneakPreviewEnabled else {
            return false
        }

        if mode == .alwaysOn {
            return isMetricPinned
        }

        return true
    }

    static func reactiveMetricToggleValue(
        storedValue: Bool,
        mode: SystemMonitorSneakMode,
        isMetricPinned: Bool
    ) -> Bool {
        return storedValue
    }

    static func alertThresholdsActive(
        systemMonitorEnabled: Bool,
        sneakPreviewEnabled: Bool
    ) -> Bool {
        systemMonitorEnabled && sneakPreviewEnabled
    }
}

private extension SystemMonitorMetric {
    func settingsTitle(language: AppLanguage) -> String {
        AppStrings.systemMonitorMetricTitle(self, language: language)
    }
}
