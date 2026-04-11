import SwiftUI

public enum SettingsPluginID: String, CaseIterable, Hashable, Sendable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }

    var iconSystemName: String {
        switch self {
        case .claude:
            return "sparkles"
        case .codex:
            return "terminal"
        }
    }

    var accentColor: Color {
        NotchPilotTheme.brand(for: self)
    }
}

public enum SettingsPane: Hashable, Sendable {
    case general
    case pluginsOverview
    case plugin(SettingsPluginID)
}

struct SettingsSidebarState: Equatable {
    var selectedPane: SettingsPane
    var isPluginsExpanded: Bool

    init(selectedPane: SettingsPane = .pluginsOverview) {
        self.selectedPane = selectedPane
        self.isPluginsExpanded = selectedPane.isPluginPane
    }

    mutating func selectGeneral() {
        selectedPane = .general
    }

    mutating func selectPluginsOverview() {
        isPluginsExpanded = true
        selectedPane = .pluginsOverview
    }

    mutating func selectPlugin(_ plugin: SettingsPluginID) {
        isPluginsExpanded = true
        selectedPane = .plugin(plugin)
    }

    mutating func togglePluginsExpanded() {
        isPluginsExpanded.toggle()
    }
}

private extension SettingsPane {
    var isPluginPane: Bool {
        switch self {
        case .general:
            return false
        case .pluginsOverview, .plugin(_):
            return true
        }
    }
}

struct PluginsOverviewSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    let onSelectPlugin: (SettingsPluginID) -> Void

    var body: some View {
        SettingsDetailScrollView(title: "插件", subtitle: "统一管理 NotchPilot 插件。选择左侧插件查看单独配置。") {
            SettingsSectionCard(
                title: "共享基础设施",
                description: "Claude 和 Codex 共用同一个 bridge/socket 基础设施。",
                accent: NotchPilotTheme.codex
            ) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(store.autoStartSocket ? NotchPilotTheme.success : Color.secondary.opacity(0.45))
                        .frame(width: 8, height: 8)

                    Text("Bridge socket")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                    Spacer()

                    Text("/tmp/notchpilot.sock")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Text("自动启动 bridge")
                        .font(.system(size: 13, weight: .medium, design: .rounded))

                    Spacer()

                    Toggle("", isOn: $store.autoStartSocket)
                        .labelsHidden()
                }
            }

            SettingsSectionCard(
                title: "已注册插件",
                description: "插件属于同一个一级导航，具体配置在子项详情里管理。",
                accent: NotchPilotTheme.codex
            ) {
                Button {
                    onSelectPlugin(.claude)
                } label: {
                    PluginOverviewRow(
                        plugin: .claude,
                        statusText: claudeStatusText,
                        statusColor: claudeStatusColor,
                        summary: "Hook bridge, approvals, session tracking"
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    onSelectPlugin(.codex)
                } label: {
                    PluginOverviewRow(
                        plugin: .codex,
                        statusText: codexStatusText,
                        statusColor: codexStatusColor,
                        summary: "Desktop IPC context, approvals, session activity"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            store.synchronizeInstallationState()
        }
    }

    private var claudeStatusText: String {
        if store.claudeCodeDetected == false {
            return "Not found"
        }
        if store.claudeHookInstalled == false {
            return "Not configured"
        }
        if store.claudeHooksNeedUpdate {
            return "Update available"
        }
        return "Connected"
    }

    private var claudeStatusColor: Color {
        if store.claudeCodeDetected == false {
            return .secondary
        }
        if store.claudeHookInstalled == false {
            return NotchPilotTheme.warning
        }
        if store.claudeHooksNeedUpdate {
            return NotchPilotTheme.warning
        }
        return NotchPilotTheme.success
    }

    private var codexStatusText: String {
        if store.codexDetected == false || store.codexDesktopConnection.status == .notFound {
            return "Not found"
        }

        switch store.codexDesktopConnection.status {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .error:
            return "Error"
        case .notFound:
            return "Not found"
        }
    }

    private var codexStatusColor: Color {
        if store.codexDetected == false || store.codexDesktopConnection.status == .notFound {
            return .secondary
        }

        switch store.codexDesktopConnection.status {
        case .disconnected:
            return NotchPilotTheme.warning
        case .connecting:
            return NotchPilotTheme.warning
        case .connected:
            return NotchPilotTheme.success
        case .error:
            return NotchPilotTheme.danger
        case .notFound:
            return .secondary
        }
    }
}

struct ClaudePluginSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    @State private var claudeError: String?
    @State private var isWorking = false

    var body: some View {
        SettingsDetailScrollView(title: "Claude", subtitle: "通过 hook 集成 Claude Code 的审批、会话和 token 数据。") {
            SettingsSectionCard(
                title: "集成状态",
                description: "Claude 插件使用 PermissionRequest、PreToolUse、PostToolUse、Session 和 Prompt hooks。",
                accent: NotchPilotTheme.claude
            ) {
                ClaudeSettingsStatusCard(
                    detected: store.claudeCodeDetected,
                    installed: store.claudeHookInstalled,
                    needsUpdate: store.claudeHooksNeedUpdate,
                    error: claudeError,
                    isWorking: isWorking,
                    installAction: installClaude,
                    uninstallAction: uninstallClaude
                )
            }

            SettingsSectionCard(
                title: "能力",
                description: "这里展示当前 Claude 插件已经接入的运行能力。",
                accent: NotchPilotTheme.claude
            ) {
                PluginCapabilityRow(icon: "checkmark.circle.fill", text: "Allow / Deny / Always Allow", isEnabled: true)
                PluginCapabilityRow(icon: "checkmark.circle.fill", text: "Session monitoring", isEnabled: true)
                PluginCapabilityRow(icon: "checkmark.circle.fill", text: "Token usage tracking", isEnabled: true)
            }
        }
        .onAppear {
            refreshInstallationState()
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
            throw HookInstallError.writeError("Bridge script not found. Place notch-bridge.py in ~/.notchpilot/")
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
        SettingsDetailScrollView(title: "Codex", subtitle: "通过 Desktop IPC 集成 Codex 的上下文、审批和会话活动。") {
            SettingsSectionCard(
                title: "集成状态",
                description: "Codex 插件只使用 Desktop IPC，不再依赖 AX。",
                accent: NotchPilotTheme.codex
            ) {
                CodexSettingsStatusCard(
                    detected: store.codexDetected,
                    connection: store.codexDesktopConnection
                )
            }

            SettingsSectionCard(
                title: "能力",
                description: "这里展示当前 Codex 插件已经接入的运行能力。",
                accent: NotchPilotTheme.codex
            ) {
                PluginCapabilityRow(
                    icon: "checkmark.circle.fill",
                    text: "Context monitoring via IPC",
                    isEnabled: store.codexDesktopConnection.status == .connected
                )
                PluginCapabilityRow(
                    icon: "checkmark.circle.fill",
                    text: "Approval actions via IPC",
                    isEnabled: store.codexDesktopConnection.status == .connected
                )
                PluginCapabilityRow(
                    icon: "checkmark.circle.fill",
                    text: "Session monitoring",
                    isEnabled: true
                )
            }
        }
        .onAppear {
            store.synchronizeInstallationState()
        }
    }
}

private struct SettingsDetailScrollView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                }

                content
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotchPilotTheme.settingsCanvas(for: colorScheme))
    }
}

private struct SettingsSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let description: String
    let accent: Color?
    let content: Content

    init(
        title: String,
        description: String,
        accent: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))

                Text(description)
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                if let accent {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(accent.opacity(0.7))
                        .frame(width: 44, height: 4)
                }
            }

            NotchPilotToolPanel(accent: accent, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(20)
            }
        }
    }
}

private struct PluginOverviewRow: View {
    let plugin: SettingsPluginID
    let statusText: String
    let statusColor: Color
    let summary: String

    var body: some View {
        HStack(spacing: 12) {
            NotchPilotIconTile(systemName: plugin.iconSystemName, accent: plugin.accentColor, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    NotchPilotStatusBadge(text: statusText, color: statusColor)
                }

                Text(summary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct ClaudeSettingsStatusCard: View {
    let detected: Bool
    let installed: Bool
    let needsUpdate: Bool
    let error: String?
    let isWorking: Bool
    let installAction: () -> Void
    let uninstallAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                NotchPilotIconTile(systemName: "sparkles", accent: NotchPilotTheme.claude, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Claude Code")
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        ClaudeStatusBadge(
                            detected: detected,
                            installed: installed,
                            needsUpdate: needsUpdate
                        )
                    }

                    Text("PermissionRequest + PreToolUse + PostToolUse + Session + Prompt hooks")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if detected {
                    if installed && needsUpdate {
                        Button("更新 Hooks", action: installAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(NotchPilotTheme.claude)
                            .disabled(isWorking)
                    } else if installed {
                        Button("卸载", action: uninstallAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isWorking)
                    } else {
                        Button("安装 Hooks", action: installAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(NotchPilotTheme.claude)
                            .disabled(isWorking)
                    }
                }
            }

            if let error, error.isEmpty == false {
                Text(error)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct CodexSettingsStatusCard: View {
    let detected: Bool
    let connection: CodexDesktopConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                NotchPilotIconTile(systemName: "terminal", accent: NotchPilotTheme.codex, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("OpenAI Codex")
                            .font(.system(size: 15, weight: .bold, design: .rounded))

                        CodexStatusBadge(
                            detected: detected,
                            connection: connection
                        )
                    }

                    Text("Desktop IPC context + approval actions")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let message = connection.message, message.isEmpty == false {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(connection.status == .error ? .red : .secondary)
            }
        }
    }
}

private struct PluginCapabilityRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let text: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isEnabled ? NotchPilotTheme.success : .secondary)

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isEnabled ? .primary : NotchPilotTheme.settingsTextSecondary(for: colorScheme))
        }
        .padding(.vertical, 2)
    }
}

private struct ClaudeStatusBadge: View {
    let detected: Bool
    let installed: Bool
    let needsUpdate: Bool

    var body: some View {
        if detected == false {
            SettingsBadge(text: "Not found", color: .secondary)
        } else if installed == false {
            SettingsBadge(text: "Not configured", color: NotchPilotTheme.warning)
        } else if needsUpdate {
            SettingsBadge(text: "Update available", color: NotchPilotTheme.warning)
        } else {
            SettingsBadge(text: "Connected", color: NotchPilotTheme.success)
        }
    }
}

private struct CodexStatusBadge: View {
    let detected: Bool
    let connection: CodexDesktopConnectionState

    var body: some View {
        if detected == false || connection.status == .notFound {
            SettingsBadge(text: "Not found", color: .secondary)
        } else {
            switch connection.status {
            case .disconnected:
                SettingsBadge(text: "Disconnected", color: NotchPilotTheme.warning)
            case .connecting:
                SettingsBadge(text: "Connecting", color: NotchPilotTheme.warning)
            case .connected:
                SettingsBadge(text: "Connected", color: NotchPilotTheme.success)
            case .error:
                SettingsBadge(text: "Error", color: NotchPilotTheme.danger)
            case .notFound:
                SettingsBadge(text: "Not found", color: .secondary)
            }
        }
    }
}

private struct SettingsBadge: View {
    let text: String
    let color: Color

    var body: some View {
        NotchPilotStatusBadge(
            text: text,
            color: color
        )
    }
}
