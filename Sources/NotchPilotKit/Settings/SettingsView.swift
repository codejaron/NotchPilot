import SwiftUI

public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = SettingsStore.shared
    @State private var sidebarState: SettingsSidebarState

    public init(selectedPane: SettingsPane = .general) {
        _sidebarState = State(initialValue: SettingsSidebarState(selectedPane: selectedPane))
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(
                    Color(nsColor: colorScheme == .dark ? .underPageBackgroundColor : .controlBackgroundColor)
                        .ignoresSafeArea(.container, edges: .top)
                )

            Rectangle()
                .fill(NotchPilotTheme.settingsDivider(for: colorScheme))
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)

            detailPane
                .background(
                    Color(nsColor: .windowBackgroundColor)
                        .ignoresSafeArea(.container, edges: .top)
                )
        }
        .frame(width: 920, height: 620)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea(.container, edges: .top))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            sidebarButton(
                title: AppStrings.text(.general, language: store.interfaceLanguage),
                systemImage: "gearshape",
                pane: .general
            )

            ForEach(SettingsPluginID.allCases) { plugin in
                sidebarButton(
                    plugin: plugin,
                    title: plugin.title(language: store.interfaceLanguage),
                    pane: .plugin(plugin)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func sidebarButton(
        plugin: SettingsPluginID? = nil,
        title: String,
        systemImage: String? = nil,
        pane: SettingsPane
    ) -> some View {
        Button {
            sidebarState.selectedPane = pane
        } label: {
            HStack(spacing: 10) {
                sidebarIcon(plugin: plugin, systemImage: systemImage)

                Text(title)
                    .font(.system(size: 14, weight: .medium))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .foregroundStyle(sidebarState.selectedPane == pane ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sidebarState.selectedPane == pane ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sidebarIcon(plugin: SettingsPluginID?, systemImage: String?) -> some View {
        if let glyph = plugin?.brandGlyph {
            NotchPilotBrandIcon(glyph: glyph, size: 15)
                .frame(width: 18)
        } else if let systemImage = systemImage ?? plugin?.iconSystemName {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 18)
        }
    }

    private var detailPane: some View {
        Group {
            switch sidebarState.selectedPane {
            case .general:
                GeneralSettingsTab()
            case let .plugin(plugin):
                switch plugin {
                case .media:
                    MediaPluginSettingsView()
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
}
