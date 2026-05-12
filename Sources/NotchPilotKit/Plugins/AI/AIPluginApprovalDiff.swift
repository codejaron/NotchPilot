import Foundation

enum AIPluginApprovalDiffLineKind: Equatable {
    case metadata
    case removal
    case addition
    case context
}

struct AIPluginApprovalDiffLinePresentation: Equatable {
    let lineNumber: String
    let prefix: String
    let text: String
    let kind: AIPluginApprovalDiffLineKind
}

struct AIPluginApprovalDiffPreview: Equatable {
    let lines: [AIPluginApprovalDiffLinePresentation]
    let isSyntaxHighlighted: Bool

    private init(lines: [AIPluginApprovalDiffLinePresentation], isSyntaxHighlighted: Bool) {
        self.lines = lines
        self.isSyntaxHighlighted = isSyntaxHighlighted
    }

    init(content: String) {
        let rawLines = Self.splitLines(content)
        let isSyntaxHighlighted = Self.looksLikeUnifiedDiff(rawLines)
        self.init(
            lines: isSyntaxHighlighted
                ? Self.parseUnifiedDiff(rawLines)
                : Self.parsePlainContent(rawLines),
            isSyntaxHighlighted: isSyntaxHighlighted
        )
    }

    init(payload: ApprovalPayload) {
        guard let proposedContent = payload.diffContent, proposedContent.isEmpty == false else {
            self.init(lines: [], isSyntaxHighlighted: false)
            return
        }

        let proposedLines = Self.splitLines(proposedContent)
        if let originalContent = payload.originalContent,
           originalContent != proposedContent {
            let generatedLines = Self.buildLineDiff(
                from: Self.splitLines(originalContent),
                to: proposedLines
            )
            self.init(
                lines: generatedLines,
                isSyntaxHighlighted: generatedLines.contains(where: {
                    $0.kind == .removal || $0.kind == .addition
                })
            )
            return
        }

        self.init(content: proposedContent)
    }

    private static func looksLikeUnifiedDiff(_ lines: [String]) -> Bool {
        if lines.contains(where: { $0.hasPrefix("@@") || $0.hasPrefix("diff ") || $0.hasPrefix("---") || $0.hasPrefix("+++") }) {
            return true
        }

        let additions = lines.filter { $0.hasPrefix("+") && $0.hasPrefix("+++") == false }.count
        let removals = lines.filter { $0.hasPrefix("-") && $0.hasPrefix("---") == false }.count
        return additions > 0 && removals > 0
    }

    private static func parsePlainContent(_ lines: [String]) -> [AIPluginApprovalDiffLinePresentation] {
        lines.enumerated().map { index, line in
            AIPluginApprovalDiffLinePresentation(
                lineNumber: "\(index + 1)",
                prefix: " ",
                text: line,
                kind: .context
            )
        }
    }

    private static func parseUnifiedDiff(_ lines: [String]) -> [AIPluginApprovalDiffLinePresentation] {
        var oldLine = 1
        var newLine = 1
        var result: [AIPluginApprovalDiffLinePresentation] = []

        for rawLine in lines {
            if rawLine.hasPrefix("@@") || rawLine.hasPrefix("diff ") || rawLine.hasPrefix("---") || rawLine.hasPrefix("+++") {
                result.append(
                    AIPluginApprovalDiffLinePresentation(
                        lineNumber: "",
                        prefix: rawLine.hasPrefix("@@") ? "@" : " ",
                        text: rawLine,
                        kind: .metadata
                    )
                )
                continue
            }

            if rawLine.hasPrefix("-") {
                result.append(
                    AIPluginApprovalDiffLinePresentation(
                        lineNumber: "\(oldLine)",
                        prefix: "-",
                        text: String(rawLine.dropFirst()),
                        kind: .removal
                    )
                )
                oldLine += 1
                continue
            }

            if rawLine.hasPrefix("+") {
                result.append(
                    AIPluginApprovalDiffLinePresentation(
                        lineNumber: "\(newLine)",
                        prefix: "+",
                        text: String(rawLine.dropFirst()),
                        kind: .addition
                    )
                )
                newLine += 1
                continue
            }

            let text = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
            result.append(
                AIPluginApprovalDiffLinePresentation(
                    lineNumber: "\(oldLine)",
                    prefix: " ",
                    text: text,
                    kind: .context
                )
            )
            oldLine += 1
            newLine += 1
        }

        return result
    }

    private static func buildLineDiff(from oldLines: [String], to newLines: [String]) -> [AIPluginApprovalDiffLinePresentation] {
        let oldCount = oldLines.count
        let newCount = newLines.count
        var longestCommonSubsequence = Array(
            repeating: Array(repeating: 0, count: newCount + 1),
            count: oldCount + 1
        )

        if oldCount > 0 && newCount > 0 {
            for oldIndex in stride(from: oldCount - 1, through: 0, by: -1) {
                for newIndex in stride(from: newCount - 1, through: 0, by: -1) {
                    if oldLines[oldIndex] == newLines[newIndex] {
                        longestCommonSubsequence[oldIndex][newIndex] =
                            longestCommonSubsequence[oldIndex + 1][newIndex + 1] + 1
                    } else {
                        longestCommonSubsequence[oldIndex][newIndex] = max(
                            longestCommonSubsequence[oldIndex + 1][newIndex],
                            longestCommonSubsequence[oldIndex][newIndex + 1]
                        )
                    }
                }
            }
        }

        var oldIndex = 0
        var newIndex = 0
        var result: [AIPluginApprovalDiffLinePresentation] = []

        while oldIndex < oldCount && newIndex < newCount {
            if oldLines[oldIndex] == newLines[newIndex] {
                result.append(
                    AIPluginApprovalDiffLinePresentation(
                        lineNumber: "\(oldIndex + 1)",
                        prefix: " ",
                        text: oldLines[oldIndex],
                        kind: .context
                    )
                )
                oldIndex += 1
                newIndex += 1
            } else if longestCommonSubsequence[oldIndex + 1][newIndex] >= longestCommonSubsequence[oldIndex][newIndex + 1] {
                result.append(
                    AIPluginApprovalDiffLinePresentation(
                        lineNumber: "\(oldIndex + 1)",
                        prefix: "-",
                        text: oldLines[oldIndex],
                        kind: .removal
                    )
                )
                oldIndex += 1
            } else {
                result.append(
                    AIPluginApprovalDiffLinePresentation(
                        lineNumber: "\(newIndex + 1)",
                        prefix: "+",
                        text: newLines[newIndex],
                        kind: .addition
                    )
                )
                newIndex += 1
            }
        }

        while oldIndex < oldCount {
            result.append(
                AIPluginApprovalDiffLinePresentation(
                    lineNumber: "\(oldIndex + 1)",
                    prefix: "-",
                    text: oldLines[oldIndex],
                    kind: .removal
                )
            )
            oldIndex += 1
        }

        while newIndex < newCount {
            result.append(
                AIPluginApprovalDiffLinePresentation(
                    lineNumber: "\(newIndex + 1)",
                    prefix: "+",
                    text: newLines[newIndex],
                    kind: .addition
                )
            )
            newIndex += 1
        }

        return result
    }

    private static func splitLines(_ content: String) -> [String] {
        var lines = content.components(separatedBy: .newlines)
        if content.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
