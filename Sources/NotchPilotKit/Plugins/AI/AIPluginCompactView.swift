import AppKit
import SwiftUI

struct AIPluginCompactView<Plugin: AIPluginRendering>: View {
    @ObservedObject var plugin: Plugin
    @ObservedObject private var settingsStore = SettingsStore.shared

    let context: NotchContext
    let approvalNotice: AIPluginApprovalSneakNotice?
    let noticeLayout: AIPluginCompactApprovalNoticeLayout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let activity = plugin.currentCompactActivity,
           let metrics = plugin.compactMetrics(context: context) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    compactBrandCluster(activity)
                        .frame(width: metrics.sideFrameWidth, alignment: .leading)

                    Spacer(minLength: context.notchGeometry.compactSize.width)

                    compactTokenCluster(activity)
                        .frame(width: metrics.sideFrameWidth, alignment: .trailing)
                }
                .frame(height: context.notchGeometry.compactSize.height, alignment: .center)

                if let approvalNotice {
                    approvalNoticeRow(approvalNotice)
                }
            }
            .padding(.horizontal, AIPluginCompactPadding.outerPadding)
            .frame(
                width: noticeLayout.totalWidth,
                height: context.notchGeometry.compactSize.height + noticeLayout.height,
                alignment: .top
            )
        } else {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 10, height: 10)
                Text(AppStrings.text(.idle, language: settingsStore.interfaceLanguage))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private func compactBrandCluster(_ activity: AIPluginCompactActivity) -> some View {
        HStack(spacing: 5) {
            if let glyph = NotchPilotBrandGlyph(host: activity.host) {
                NotchPilotBrandIcon(glyph: glyph, size: 22)
            } else {
                NotchPilotIconTile(
                    systemName: plugin.iconSystemName,
                    accent: plugin.accentColor,
                    size: 30,
                    isActive: true
                )
            }

            if activity.approvalCount > 0 {
                NotchPilotStatusBadge(
                    text: "\(activity.approvalCount)",
                    color: NotchPilotTheme.brand(for: activity.host),
                    foreground: .white
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            if let runtime = activity.runtimeDurationText, runtime.isEmpty == false {
                Text(runtime)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    private func compactTokenCluster(_ activity: AIPluginCompactActivity) -> some View {
        if activity.inputTokenCount != nil || activity.outputTokenCount != nil {
            VStack(alignment: .trailing, spacing: 0) {
                tokenChip(symbol: "↑", value: activity.inputTokenCount)
                tokenChip(symbol: "↓", value: activity.outputTokenCount)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func approvalNoticeRow(_ notice: AIPluginApprovalSneakNotice) -> some View {
        Text(localizedApprovalNoticeText(notice.text))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary.opacity(0.92))
            .lineLimit(noticeLayout.lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: noticeLayout.height, alignment: noticeLayout.isSingleLine ? .center : .top)
    }

    private func localizedApprovalNoticeText(_ text: String) -> String {
        let language = settingsStore.interfaceLanguage
        let codexSummary = AppStrings.codexSurfaceSummary(text, language: language)
        let claudeTitle = AppStrings.claudeApprovalTitle(codexSummary, language: language)
        return AppStrings.activityLabel(claudeTitle, language: language)
    }

    private func tokenChip(symbol: String, value: Int?) -> some View {
        Text("\(symbol)\(plugin.formattedTokenCount(value))")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.82))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
