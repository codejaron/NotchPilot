import AppKit
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        SettingsPage(title: "通用") {
            SettingsGroupSection(title: "审批") {
                SettingsToggleRow(
                    title: "显示 Claude / Codex 审批弹窗",
                    detail: "关闭后不主动弹出审批提示。",
                    isOn: $store.approvalSneakNotificationsEnabled
                )
            }

            SettingsGroupSection(title: "应用") {
                SettingsActionRow(
                    title: "退出应用",
                    detail: "结束 NotchPilot，并关闭状态栏和 Notch 窗口。",
                    buttonTitle: "退出应用",
                    role: .destructive
                ) {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
