import SwiftUI

public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebarState: SettingsSidebarState

    public init(selectedPane: SettingsPane = .pluginsOverview) {
        _sidebarState = State(initialValue: SettingsSidebarState(selectedPane: selectedPane))
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.55),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)

            detailPane
        }
        .frame(width: 960, height: 620)
        .background(NotchPilotTheme.settingsCanvas(for: colorScheme))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            sidebarHeader

            VStack(alignment: .leading, spacing: 6) {
                sidebarRow(
                    title: "通用",
                    subtitle: "应用级偏好",
                    systemImage: "slider.horizontal.3",
                    accent: .secondary,
                    isSelected: sidebarState.selectedPane == .general,
                    action: {
                        sidebarState.selectGeneral()
                    }
                )

                pluginsSidebarGroup
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 276)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(NotchPilotTheme.settingsSidebarFill(for: colorScheme))
        )
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                NotchPilotTheme.codex.opacity(0.9),
                                NotchPilotTheme.claude.opacity(0.8),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "capsule.bottomhalf.filled")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("NotchPilot")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Settings")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                }
            }

            Text("Manage the dynamic island shell, plugins, and bridge integrations.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.52))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.6), lineWidth: 1)
        }
    }

    private var pluginsSidebarGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarState.selectPluginsOverview()
                    }
                } label: {
                    HStack(spacing: 10) {
                        NotchPilotIconTile(
                            systemName: "puzzlepiece.extension.fill",
                            accent: NotchPilotTheme.codex,
                            size: 30
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("插件")
                                .font(.system(size: 13, weight: .bold, design: .rounded))

                            Text("Claude / Codex / System")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                        }

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarState.togglePluginsExpanded()
                    }
                } label: {
                    Image(systemName: sidebarState.isPluginsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.48))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        sidebarState.selectedPane == .pluginsOverview
                            ? NotchPilotTheme.settingsSelectionFill(accent: NotchPilotTheme.codex, colorScheme: colorScheme)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        sidebarState.selectedPane == .pluginsOverview
                            ? NotchPilotTheme.settingsSelectionStroke(accent: NotchPilotTheme.codex, colorScheme: colorScheme)
                            : Color.clear,
                        lineWidth: 1
                    )
            )

            if sidebarState.isPluginsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SettingsPluginID.allCases) { plugin in
                        sidebarRow(
                            title: plugin.title,
                            subtitle: sidebarSubtitle(for: plugin),
                            systemImage: plugin.iconSystemName,
                            accent: plugin.accentColor,
                            isSelected: sidebarState.selectedPane == .plugin(plugin),
                            indentation: 14,
                            action: {
                                sidebarState.selectPlugin(plugin)
                            }
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var detailPane: some View {
        Group {
            switch sidebarState.selectedPane {
            case .general:
                GeneralSettingsTab()
            case .pluginsOverview:
                PluginsOverviewSettingsView { plugin in
                    sidebarState.selectPlugin(plugin)
                }
            case let .plugin(plugin):
                switch plugin {
                case .claude:
                    ClaudePluginSettingsView()
                case .codex:
                    CodexPluginSettingsView()
                case .systemMonitor:
                    SystemMonitorPluginSettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarSubtitle(for plugin: SettingsPluginID) -> String {
        switch plugin {
        case .claude:
            return "Hooks + approvals"
        case .codex:
            return "IPC + approvals"
        case .systemMonitor:
            return "System metrics"
        }
    }

    private func sidebarRow(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        isSelected: Bool,
        indentation: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NotchPilotIconTile(
                    systemName: systemImage,
                    accent: accent,
                    size: 30,
                    isActive: isSelected
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, indentation)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                            ? NotchPilotTheme.settingsSelectionFill(accent: accent, colorScheme: colorScheme)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? NotchPilotTheme.settingsSelectionStroke(accent: accent, colorScheme: colorScheme)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
