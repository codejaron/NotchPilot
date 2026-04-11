import AppKit
import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                header

                NotchPilotToolPanel(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionHeader(
                            eyebrow: "Window Behavior",
                            title: "工具窗与系统壳层分离",
                            description: "关闭设置窗口不会退出 NotchPilot，Notch 主壳层会继续保持常驻。"
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            infoRow(
                                icon: "capsule.bottomhalf.filled",
                                title: "Notch 常驻",
                                detail: "Notch 主界面保持独立的灵动岛视觉与悬浮窗口行为。"
                            )
                            infoRow(
                                icon: "gearshape.2.fill",
                                title: "设置独立",
                                detail: "应用级偏好与插件配置都集中在这里，避免与运行时交互混在一起。"
                            )
                        }
                    }
                    .padding(24)
                }

                NotchPilotToolPanel(accent: NotchPilotTheme.codex, cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionHeader(
                            eyebrow: "Approval Alerts",
                            title: "审批通知",
                            description: "有待审批时，在 Notch 下方显示一行命令通知。"
                        )

                        Toggle(isOn: $store.approvalSneakNotificationsEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("显示审批通知条")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                Text("关闭后只在 logo 旁显示待审批数量，不弹出下方命令行。")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(24)
                }

                NotchPilotToolPanel(accent: NotchPilotTheme.warning, cornerRadius: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Session Control")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))

                            Text("退出应用")
                                .font(.system(size: 18, weight: .bold, design: .rounded))

                            Text("完全结束 NotchPilot 进程，包括状态栏项、bridge 和多屏 Notch 壳层。")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                        }

                        Spacer()

                        Button("退出应用", role: .destructive) {
                            NSApp.terminate(nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NotchPilotTheme.warning)
                    }
                    .padding(24)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotchPilotTheme.settingsCanvas(for: colorScheme))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("General")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("应用级偏好与窗口行为。插件细节保持在左侧插件导航里。")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
            }

            Spacer()

            NotchPilotStatusBadge(
                text: colorScheme == .dark ? "Dark Adaptive" : "Light Adaptive",
                color: .secondary,
                foreground: colorScheme == .dark ? .white.opacity(0.86) : .primary
            )
        }
    }

    private func sectionHeader(eyebrow: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))

            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(description)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
        }
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            NotchPilotIconTile(systemName: icon, accent: NotchPilotTheme.codex, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.56))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.5), lineWidth: 1)
        }
    }
}
