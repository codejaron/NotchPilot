import SwiftUI

struct AIPluginApprovalCommandView: View {
    let text: String
    var compact = false

    var body: some View {
        let cornerRadius = compact ? CodexApprovalCompactLayout.commandCornerRadius : 12

        Text(text)
            .font(.system(
                size: compact ? CodexApprovalCompactLayout.commandFontSize : 12,
                weight: .regular,
                design: .monospaced
            ))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary.opacity(0.88))
            .lineLimit(compact ? CodexApprovalCompactLayout.commandLineLimit : 4)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? CodexApprovalCompactLayout.commandHorizontalPadding : 10)
            .padding(.vertical, compact ? CodexApprovalCompactLayout.commandVerticalPadding : 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
