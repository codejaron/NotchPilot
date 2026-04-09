import SwiftUI

public struct SettingsView: View {
    @State private var sidebarState: SettingsSidebarState

    public init(selectedPane: SettingsPane = .pluginsOverview) {
        _sidebarState = State(initialValue: SettingsSidebarState(selectedPane: selectedPane))
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            detailPane
        }
        .frame(width: 820, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            sidebarRow(
                title: "通用",
                systemImage: "gearshape",
                isSelected: sidebarState.selectedPane == .general,
                action: {
                    sidebarState.selectGeneral()
                }
            )

            pluginsSidebarGroup

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var pluginsSidebarGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 16)

                    Text("插件")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarState.selectPluginsOverview()
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarState.togglePluginsExpanded()
                    }
                } label: {
                    Image(systemName: sidebarState.isPluginsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(sidebarState.selectedPane == .pluginsOverview ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        sidebarState.selectedPane == .pluginsOverview ? Color.accentColor.opacity(0.28) : Color.clear,
                        lineWidth: 1
                    )
            )

            if sidebarState.isPluginsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsPluginID.allCases) { plugin in
                        sidebarRow(
                            title: plugin.title,
                            systemImage: plugin.iconSystemName,
                            isSelected: sidebarState.selectedPane == .plugin(plugin),
                            indentation: 18,
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
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarRow(
        title: String,
        systemImage: String,
        isSelected: Bool,
        indentation: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer(minLength: 0)
            }
            .padding(.leading, indentation)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.28) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
