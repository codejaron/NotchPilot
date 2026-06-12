import CoreGraphics

struct CodexApprovalTextInputSizing: Equatable {
    let lineHeight: CGFloat
    let verticalPadding: CGFloat

    var minimumHeight: CGFloat {
        (lineHeight * 2) + verticalPadding
    }

    var maximumHeight: CGFloat {
        (lineHeight * 4) + verticalPadding
    }

    func height(forContentHeight contentHeight: CGFloat) -> CGFloat {
        min(max(contentHeight + verticalPadding, minimumHeight), maximumHeight)
    }
}

enum CodexApprovalCompactLayout {
    static let detailSpacing: CGFloat = 6
    static let headerSpacing: CGFloat = 7
    static let headerButtonSize: CGFloat = 24
    static let headerSummaryFontSize: CGFloat = 13
    static let headerSummaryLineHeight: CGFloat = 16
    static let headerSummaryLineLimit = 2

    static let primaryColumnSpacing: CGFloat = 6
    static let commandFontSize: CGFloat = 11
    static let commandLineHeight: CGFloat = 14
    static let commandLineLimit = 2
    static let commandHorizontalPadding: CGFloat = 8
    static let commandVerticalPadding: CGFloat = 5
    static let commandCornerRadius: CGFloat = 8

    static let controlsSpacing: CGFloat = 6
    static let optionStackSpacing: CGFloat = 4
    static let optionContentSpacing: CGFloat = 8
    static let optionIndexSize: CGFloat = 20
    static let optionIndexFontSize: CGFloat = 10
    static let optionTitleFontSize: CGFloat = 11
    static let optionLineHeight: CGFloat = 14
    static let optionLineLimit = 2
    static let optionHorizontalPadding: CGFloat = 10
    static let optionVerticalPadding: CGFloat = 5
    static let optionCornerRadius: CGFloat = 8

    static let actionSpacing: CGFloat = 6
    static let actionFontSize: CGFloat = 10
    static let actionHorizontalPadding: CGFloat = 9
    static let actionVerticalPadding: CGFloat = 5

    static let textInputFontSize: CGFloat = 11
    static let textInputLineHeight: CGFloat = 14
    static let textInputVerticalPadding: CGFloat = 8
    static let textInputLeadingInset: CGFloat = 24
    static let textInputIndexLeadingPadding: CGFloat = 9
    static let textInputIndexTopPadding: CGFloat = 8
    static let textInputCornerRadius: CGFloat = 8
    static let placeholderHorizontalPadding: CGFloat = 9
    static let placeholderVerticalPadding: CGFloat = 8

    static var commandSingleLineHeight: CGFloat {
        commandLineHeight + (commandVerticalPadding * 2)
    }

    static var optionRowHeight: CGFloat {
        max(optionIndexSize, optionLineHeight) + (optionVerticalPadding * 2)
    }

    static var textInputMinimumHeight: CGFloat {
        CodexApprovalTextInputSizing(
            lineHeight: textInputLineHeight,
            verticalPadding: textInputVerticalPadding
        ).minimumHeight
    }

    static func estimatedDetailHeight(
        optionCount: Int,
        commandLineCount: Int,
        includesTextInput: Bool,
        headerLineCount: Int
    ) -> CGFloat {
        let headerLines = max(1, min(headerLineCount, headerSummaryLineLimit))
        let headerHeight = max(headerButtonSize, CGFloat(headerLines) * headerSummaryLineHeight)
        let commandLines = max(1, min(commandLineCount, commandLineLimit))
        let commandHeight = CGFloat(commandLines) * commandLineHeight + (commandVerticalPadding * 2)

        let safeOptionCount = max(0, optionCount)
        let optionsHeight = safeOptionCount == 0
            ? 0
            : CGFloat(safeOptionCount) * optionRowHeight
                + CGFloat(max(0, safeOptionCount - 1)) * optionStackSpacing
        let inputHeight = includesTextInput ? textInputMinimumHeight : 0
        let controlGroupCount = (safeOptionCount > 0 ? 1 : 0) + (includesTextInput ? 1 : 0)
        let controlsHeight =
            optionsHeight
            + inputHeight
            + CGFloat(max(0, controlGroupCount - 1)) * controlsSpacing

        return headerHeight
            + detailSpacing
            + commandHeight
            + (controlsHeight > 0 ? primaryColumnSpacing + controlsHeight : 0)
    }
}
