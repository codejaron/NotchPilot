import AppKit
import SwiftUI

struct GeneralSettingsTab: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("通用")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("应用级偏好放在这里，插件设置单独归到“插件”导航里。")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("退出应用", role: .destructive) {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("窗口行为")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("关闭设置窗口不会退出 NotchPilot。")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Notch 行为、外观和其他应用级偏好后续继续挂在这里，不再和插件配置混在一起。")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
