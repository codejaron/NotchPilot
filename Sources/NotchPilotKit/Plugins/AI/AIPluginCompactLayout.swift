import AppKit

struct AIPluginCompactMetrics {
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let sideFrameWidth: CGFloat
    let totalWidth: CGFloat
}

enum AIPluginCompactPadding {
    static let outerPadding: CGFloat = 10
}

enum AICompactTextMeasurer {
    static func width(_ text: String, font: NSFont) -> CGFloat {
        guard text.isEmpty == false else {
            return 0
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    static func height(_ text: String, font: NSFont, constrainedTo width: CGFloat) -> CGFloat {
        guard text.isEmpty == false, width > 0 else {
            return 0
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(bounds.height)
    }
}

struct AIPluginCompactApprovalNoticeLayout: Equatable {
    static let singleLineHeight: CGFloat = 32
    static let horizontalInsets: CGFloat = 12
    static let verticalInsets: CGFloat = 10
    static let maxTextWidth: CGFloat = 520

    let totalWidth: CGFloat
    let height: CGFloat
    let lineLimit: Int?

    init(
        notice: AIPluginApprovalSneakNotice?,
        baseTotalWidth: CGFloat,
        outerPadding: CGFloat = AIPluginCompactPadding.outerPadding
    ) {
        guard let text = notice?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false
        else {
            self.totalWidth = baseTotalWidth
            self.height = 0
            self.lineLimit = 1
            return
        }

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let measuredTextWidth = AICompactTextMeasurer.width(text, font: font)
        let baseTextWidth = max(1, baseTotalWidth - (outerPadding * 2) - Self.horizontalInsets)
        let targetTextWidth = min(Self.maxTextWidth, max(baseTextWidth, measuredTextWidth))
        let additionalWidth = max(0, targetTextWidth - baseTextWidth)
        let measuredTextHeight = AICompactTextMeasurer.height(
            text,
            font: font,
            constrainedTo: targetTextWidth
        )

        self.totalWidth = baseTotalWidth + additionalWidth
        self.height = max(Self.singleLineHeight, measuredTextHeight + Self.verticalInsets)
        self.lineLimit = nil
    }

    var isSingleLine: Bool {
        height <= Self.singleLineHeight
    }
}
