import SwiftUI

public enum SettingsPluginID: String, CaseIterable, Hashable, Sendable, Identifiable {
    case systemMonitor = "system-monitor"
    case claude
    case codex
    case media = "media-playback"

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .media:
            return "Media"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .systemMonitor:
            return "System"
        }
    }

    var iconSystemName: String {
        switch self {
        case .media:
            return "play.circle.fill"
        case .claude:
            return "sparkles"
        case .codex:
            return "terminal"
        case .systemMonitor:
            return "speedometer"
        }
    }

    var sidebarSubtitle: String {
        switch self {
        case .media:
            return "媒体播放"
        case .claude:
            return "Claude 集成"
        case .codex:
            return "连接状态"
        case .systemMonitor:
            return "系统监控"
        }
    }
}

struct ClaudeSettingsStatusText: Equatable {
    let value: String

    init(detected: Bool, installed: Bool, needsUpdate: Bool) {
        if detected == false {
            value = "未检测到"
        } else if installed == false {
            value = "未安装"
        } else if needsUpdate {
            value = "可更新"
        } else {
            value = "已连接"
        }
    }
}

struct MediaPluginSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        SettingsPage(title: "Media") {
            SettingsGroupSection(title: "播放") {
                SettingsToggleRow(
                    title: "启用媒体插件",
                    detail: "跟随当前 macOS Now Playing 播放会话。",
                    isOn: $store.mediaPlaybackEnabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: "播放变化时显示预览",
                    detail: "在 Notch 闭合态显示当前播放信息。",
                    isOn: $store.mediaPlaybackSneakPreviewEnabled
                )
            }
        }
    }
}

struct CodexSettingsStatusText: Equatable {
    let value: String

    init(detected: Bool, connection: CodexDesktopConnectionState) {
        if detected == false || connection.status == .notFound {
            value = "未检测到"
            return
        }

        switch connection.status {
        case .disconnected:
            value = "未连接"
        case .connecting:
            value = "连接中"
        case .connected:
            value = "已连接"
        case .error:
            value = "错误"
        case .notFound:
            value = "未检测到"
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
            SettingsGroupSection(title: "Claude Code") {
                SettingsStatusRow(
                    title: "集成状态",
                    value: claudeStatusText.value,
                    valueColor: claudeStatusColor
                )

                SettingsRowDivider()

                SettingsActionRow(
                    title: "操作",
                    detail: claudeActionDetail,
                    buttonTitle: claudeActionTitle,
                    isEnabled: store.claudeCodeDetected && isWorking == false
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
            needsUpdate: store.claudeHooksNeedUpdate
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
            return store.claudeHooksNeedUpdate ? "更新集成" : "移除集成"
        }
        return "安装集成"
    }

    private var claudeActionDetail: String? {
        store.claudeCodeDetected ? nil : "请先安装 Claude Code。"
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
        if store.bridgeScriptPath.isEmpty == false,
           FileManager.default.fileExists(atPath: store.bridgeScriptPath) {
            return store.bridgeScriptPath
        }

        if let bundledURL = Bundle.module.url(forResource: "notch-bridge", withExtension: "py") {
            let path = try HookInstaller().installBridgeScript(fromBundle: bundledURL.path)
            store.bridgeScriptPath = path
            return path
        }

        let fallbackPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchpilot/notch-bridge.py")
            .path
        guard FileManager.default.fileExists(atPath: fallbackPath) else {
            throw HookInstallError.writeError("未找到 Claude 集成所需脚本，无法完成安装。")
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
            SettingsGroupSection(title: "Codex Desktop") {
                SettingsStatusRow(
                    title: "连接状态",
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
            connection: store.codexDesktopConnection
        )
    }

    private var codexStatusColor: Color {
        store.codexDesktopConnection.status == .error ? .red : .secondary
    }
}

struct SystemMonitorPluginSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        SettingsPage(title: "System") {
            SettingsGroupSection(title: "预览") {
                SettingsToggleRow(
                    title: "在 Notch 闭合态显示系统监控",
                    isOn: $store.systemMonitorSneakPreviewEnabled
                )

                SettingsRowDivider()

                SettingsPickerRow(
                    title: "左侧槽位 1",
                    selection: metricBinding(side: .left, index: 0),
                    isEnabled: store.systemMonitorSneakPreviewEnabled
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: "左侧槽位 2",
                    selection: metricBinding(side: .left, index: 1),
                    isEnabled: store.systemMonitorSneakPreviewEnabled
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: "右侧槽位 1",
                    selection: metricBinding(side: .right, index: 0),
                    isEnabled: store.systemMonitorSneakPreviewEnabled
                ) {
                    metricOptions
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    title: "右侧槽位 2",
                    selection: metricBinding(side: .right, index: 1),
                    isEnabled: store.systemMonitorSneakPreviewEnabled
                ) {
                    metricOptions
                }
            }
        }
    }

    @ViewBuilder
    private var metricOptions: some View {
        Text("隐藏")
            .tag(SystemMonitorMetric?.none)

        ForEach(SystemMonitorMetric.allCases, id: \.self) { metric in
            Text(metric.settingsTitle)
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
                left: updatedMetrics(configuration.leftMetrics, setting: metric, at: index),
                right: configuration.rightMetrics
            )
        case .right:
            store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
                left: configuration.leftMetrics,
                right: updatedMetrics(configuration.rightMetrics, setting: metric, at: index)
            )
        }
    }

    private func updatedMetrics(
        _ metrics: [SystemMonitorMetric],
        setting metric: SystemMonitorMetric?,
        at index: Int
    ) -> [SystemMonitorMetric] {
        var updatedMetrics = Array(metrics.prefix(SystemMonitorSneakConfiguration.defaultLimit))

        if let metric {
            updatedMetrics.removeAll { $0 == metric }
            updatedMetrics.insert(metric, at: min(index, updatedMetrics.count))
        } else if updatedMetrics.indices.contains(index) {
            updatedMetrics.remove(at: index)
        }

        return Array(updatedMetrics.prefix(SystemMonitorSneakConfiguration.defaultLimit))
    }
}

private enum SystemMonitorSneakSide {
    case left
    case right
}

private extension SystemMonitorMetric {
    var settingsTitle: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "内存"
        case .network:
            return "网络"
        case .disk:
            return "磁盘剩余"
        case .temperature:
            return "温度"
        case .battery:
            return "电量"
        }
    }
}
