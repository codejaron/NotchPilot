import SwiftUI

enum AIPluginApprovalStyle {
    static func foregroundColor(for style: ApprovalActionStyle) -> Color {
        switch style {
        case .primary:
            return .white
        case .secondary, .destructive, .outline:
            return .white
        }
    }

    static func backgroundFill(for style: ApprovalActionStyle, accent: Color) -> Color {
        switch style {
        case .primary:
            return accent.opacity(0.94)
        case .secondary:
            return accent.opacity(0.24)
        case .destructive:
            return NotchPilotTheme.danger.opacity(0.28)
        case .outline:
            return Color.white.opacity(0.06)
        }
    }

    static func borderColor(for style: ApprovalActionStyle, accent: Color) -> Color {
        switch style {
        case .primary:
            return Color.white.opacity(0.14)
        case .secondary:
            return accent.opacity(0.34)
        case .destructive:
            return NotchPilotTheme.danger.opacity(0.34)
        case .outline:
            return Color.white.opacity(0.16)
        }
    }

    static func borderLineWidth(for style: ApprovalActionStyle) -> CGFloat {
        style == .primary ? 0 : 1
    }
}
