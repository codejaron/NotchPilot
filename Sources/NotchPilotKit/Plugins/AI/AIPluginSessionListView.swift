import AppKit
import SwiftUI

/// Renders the AI session list in the expanded notch view.
///
/// Host-agnostic: the row's brand glyph and accent color are derived from
/// `summary.host`, so this view can be reused across multiple AI plugins
/// (or by the merged AI tab in Phase 4).
struct AIPluginSessionListView: View {
    let summaries: [AIPluginExpandedSessionSummary]
    let onActivate: (AIPluginExpandedSessionSummary) -> Void
    let onJump: ((AIPluginExpandedSessionSummary) -> Void)?

    var body: some View {
        let presentation = AIPluginExpandedSessionListPresentation(summaries: summaries)
        if presentation.shouldRender {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summaries) { summary in
                    AIPluginSessionRow(
                        summary: summary,
                        onActivate: { onActivate(summary) },
                        onJump: onJump.map { jump in
                            { jump(summary) }
                        }
                    )
                }
            }
        }
    }
}

private struct AIPluginSessionRow: View {
    let summary: AIPluginExpandedSessionSummary
    let onActivate: () -> Void
    let onJump: (() -> Void)?

    @ObservedObject private var settingsStore = SettingsStore.shared

    private var glyph: NotchPilotBrandGlyph? {
        NotchPilotBrandGlyph(host: summary.host)
    }

    private var accent: Color {
        NotchPilotTheme.brand(for: summary.host)
    }

    var body: some View {
        let jumpAccessory = AIPluginSessionJumpAccessoryPresentation(isRowDimmed: summary.isDimmed)

        HStack(spacing: 4) {
            Button(action: onActivate) {
                HStack(spacing: 10) {
                    attentionAccent

                    if let glyph {
                        NotchPilotBrandIcon(glyph: glyph, size: 20)
                    } else {
                        // Defensive fallback; NotchPilotBrandGlyph(host:) covers all
                        // AIHost cases today, but keep a safe default if a new host
                        // gets added without a glyph mapping.
                        NotchPilotIconTile(
                            systemName: "sparkles",
                            accent: accent,
                            size: 20,
                            isActive: summary.hasAttention
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(AppStrings.activityLabel(summary.subtitle, language: settingsStore.interfaceLanguage))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(
                                summary.hasAttention
                                    ? accent.opacity(0.92)
                                    : NotchPilotTheme.islandTextSecondary
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 6)

                    if summary.hasMeta {
                        sessionMetaColumn
                    }

                    if onJump == nil {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.22))
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, onJump == nil ? 8 : 4)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(jumpAccessory.primaryContentOpacity)

            if let onJump {
                Button(action: onJump) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(jumpAccessory.backgroundOpacity))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(jumpAccessory.borderOpacity), lineWidth: 1)
                            )

                        Image(systemName: jumpAccessory.symbolSystemName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(jumpAccessory.symbolOpacity))
                    }
                    .frame(width: jumpAccessory.iconFrameSize, height: jumpAccessory.iconFrameSize)
                    .frame(width: summary.jumpAccessoryHitWidth, height: jumpAccessory.hitHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open session")
            }
        }
    }

    private var attentionAccent: some View {
        Capsule()
            .fill(summary.hasAttention ? accent : Color.clear)
            .frame(width: 2, height: 22)
    }

    @ViewBuilder
    private var sessionMetaColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if summary.hasTokenUsage {
                HStack(spacing: 6) {
                    Text("↑\(formattedTokenCount(summary.inputTokenCount))")
                    Text("↓\(formattedTokenCount(summary.outputTokenCount))")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            if let runtime = summary.runtimeDurationText, runtime.isEmpty == false {
                Text(runtime)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchPilotTheme.islandTextMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func formattedTokenCount(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
