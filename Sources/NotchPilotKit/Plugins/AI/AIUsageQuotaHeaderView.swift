import AppKit
import SwiftUI

struct AIUsageQuotaHeaderView: View {
    let snapshots: [AIUsageQuotaSnapshot]

    var body: some View {
        let presentation = AIUsageQuotaHeaderPresentation(snapshots: snapshots)
        if presentation.shouldRender {
            HStack(spacing: 6) {
                ForEach(presentation.items) { item in
                    quotaChip(item)
                }
            }
            .frame(height: 24)
        }
    }

    private func quotaChip(_ item: AIUsageQuotaHeaderPresentation.Item) -> some View {
        HStack(spacing: 5) {
            if let glyph = NotchPilotBrandGlyph(host: item.host) {
                NotchPilotBrandIcon(glyph: glyph, size: 12)
            } else {
                NotchPilotIconTile(
                    systemName: "sparkles",
                    accent: NotchPilotTheme.brand(for: item.host),
                    size: 12,
                    isActive: false
                )
            }

            Text(item.title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.92))
                .lineLimit(1)

            ForEach(item.windows) { window in
                HStack(spacing: 2) {
                    Text(window.title)
                        .foregroundStyle(NotchPilotTheme.islandTextMuted.opacity(0.92))
                    Text(window.remainingPercentText)
                        .foregroundStyle(NotchPilotTheme.islandTextPrimary.opacity(0.88))
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityLabel(item.accessibilityText)
        .help(helpText(for: item))
    }

    private func helpText(for item: AIUsageQuotaHeaderPresentation.Item) -> String {
        let resetParts = item.windows.compactMap { window -> String? in
            guard let resetText = window.resetText else {
                return nil
            }
            return "\(window.title) resets in \(resetText)"
        }
        guard resetParts.isEmpty == false else {
            return item.accessibilityText
        }
        return "\(item.accessibilityText)\n\(resetParts.joined(separator: "\n"))"
    }
}
