import AppKit
import SwiftUI

@MainActor
protocol AIPluginRendering: NotchPlugin {
    var sessions: [AISession] { get }
    var pendingApprovals: [PendingApproval] { get }
    var codexActionableSurface: CodexActionableSurface? { get }
    var currentCompactActivity: AIPluginCompactActivity? { get }
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] { get }
    var approvalSneakNotificationsEnabled: Bool { get }

    func displayTitle(for session: AISession) -> String?
    func expandedSessionTitle(for session: AISession) -> String
    func preferredCodexTitle(for surface: CodexActionableSurface?) -> String?
    func respond(to requestID: String, with action: ApprovalAction)

    @discardableResult
    func performCodexAction(_ action: CodexSurfaceAction, surfaceID: String) -> Bool

    @discardableResult
    func selectCodexOption(_ optionID: String, surfaceID: String) -> Bool

    @discardableResult
    func updateCodexText(_ text: String, surfaceID: String) -> Bool
}

extension AIPluginRendering {
    public func preview(context: NotchContext) -> NotchPluginPreview? {
        guard shouldRenderCompactPreview else {
            return nil
        }
        guard let metrics = compactMetrics(context: context) else {
            return nil
        }
        let approvalNotice = approvalSneakNotice()
        let noticeLayout = AIPluginCompactApprovalNoticeLayout(
            notice: approvalNotice,
            baseTotalWidth: metrics.totalWidth
        )

        return NotchPluginPreview(
            width: noticeLayout.totalWidth,
            height: context.notchGeometry.compactSize.height + noticeLayout.height,
            view: AnyView(
                AIPluginCompactView(
                    plugin: self,
                    context: context,
                    approvalNotice: approvalNotice,
                    noticeLayout: noticeLayout
                )
            )
        )
    }

    public func contentView(context: NotchContext) -> AnyView {
        AnyView(AIPluginExpandedView(plugin: self))
    }

    var shouldRenderCompactPreview: Bool {
        (approvalSneakNotificationsEnabled && approvalDrivenCompactPreviewAvailable)
            || compactPreviewSession() != nil
    }

    func compactPreviewSession() -> AISession? {
        sessions
            .filter(\.isLiveCompactPreviewCandidate)
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    func compactMetrics(context: NotchContext) -> AIPluginCompactMetrics? {
        guard let activity = currentCompactActivity else {
            return nil
        }

        let leftWidth =
            22
            + (activity.approvalCount > 0 ? 5 + approvalBadgeWidth(count: activity.approvalCount) : 0)

        let rightWidth =
            tokenWidth(symbol: "↑", value: activity.inputTokenCount)
            + 6
            + tokenWidth(symbol: "↓", value: activity.outputTokenCount)

        let sideFrameWidth = max(34, leftWidth, rightWidth)
        let totalWidth =
            AIPluginCompactLayout.outerPadding * 2
            + context.notchGeometry.compactSize.width
            + sideFrameWidth * 2

        return AIPluginCompactMetrics(
            leftWidth: leftWidth,
            rightWidth: rightWidth,
            sideFrameWidth: sideFrameWidth,
            totalWidth: totalWidth
        )
    }

    func expandedSessionTitle(for session: AISession) -> String {
        displayTitle(for: session) ?? hostDisplayName(for: session.host)
    }

    func preferredCodexTitle(for surface: CodexActionableSurface?) -> String? { nil }

    var approvalSneakNotificationsEnabled: Bool {
        SettingsStore.shared.approvalSneakNotificationsEnabled
    }

    func approvalSneakNotice() -> AIPluginApprovalSneakNotice? {
        guard approvalSneakNotificationsEnabled else {
            return nil
        }

        return AIPluginApprovalSneakNotice(
            pendingApprovals: pendingApprovals,
            codexSurface: codexActionableSurface
        )
    }

    func respond(to requestID: String, with action: ApprovalAction) {}

    @discardableResult
    func performCodexAction(_ action: CodexSurfaceAction, surfaceID: String) -> Bool { false }

    @discardableResult
    func selectCodexOption(_ optionID: String, surfaceID: String) -> Bool { false }

    @discardableResult
    func updateCodexText(_ text: String, surfaceID: String) -> Bool { false }

    func hostDisplayName(for host: AIHost) -> String {
        host == .claude ? "Claude Code" : "OpenAI Codex"
    }

    private var approvalDrivenCompactPreviewAvailable: Bool {
        codexActionableSurface != nil || pendingApprovals.isEmpty == false
    }

    func formattedTokenCount(_ value: Int?) -> String {
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

    private func tokenWidth(symbol: String, value: Int?) -> CGFloat {
        AICompactTextMeasurer.width(
            "\(symbol)\(formattedTokenCount(value))",
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
    }

    private func approvalBadgeWidth(count: Int) -> CGFloat {
        AICompactTextMeasurer.width(
            "\(count)",
            font: .systemFont(ofSize: 10, weight: .semibold)
        ) + 10
    }
}

struct AIPluginCompactActivity: Equatable {
    let host: AIHost
    let label: String
    let inputTokenCount: Int?
    let outputTokenCount: Int?
    let approvalCount: Int
    let sessionTitle: String?
    let runtimeDurationText: String?
}

private extension AISession {
    var isLiveCompactPreviewCandidate: Bool {
        switch lastEventType {
        case .preToolUse, .userPromptSubmit, .unknown:
            return true
        case .permissionRequest, .postToolUse, .sessionStart, .stop:
            return false
        }
    }
}

struct AIPluginApprovalSneakNotice: Equatable {
    let count: Int
    let text: String

    init?(pendingApprovals: [PendingApproval], codexSurface: CodexActionableSurface?) {
        if let codexSurface {
            self.count = max(1, pendingApprovals.count)
            self.text = Self.codexText(for: codexSurface)
            return
        }

        guard let approval = pendingApprovals.first else {
            return nil
        }

        self.count = pendingApprovals.count
        self.text = Self.approvalText(for: approval)
    }

    private static func codexText(for surface: CodexActionableSurface) -> String {
        let summary = surface.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return summary
        }

        if let commandPreview = surface.commandPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           commandPreview.isEmpty == false {
            return commandPreview
        }

        return surface.summary
    }

    private static func approvalText(for approval: PendingApproval) -> String {
        if let command = approval.payload.command?.trimmingCharacters(in: .whitespacesAndNewlines),
           command.isEmpty == false {
            return command
        }

        if let networkApprovalContext = approval.networkApprovalContext {
            let portSuffix = networkApprovalContext.port.map { ":\($0)" } ?? ""
            return "\(networkApprovalContext.protocolName.uppercased()) \(networkApprovalContext.host)\(portSuffix)"
        }

        if approval.payload.previewText.isEmpty == false {
            return approval.payload.previewText
        }

        if let filePath = approval.payload.filePath, filePath.isEmpty == false {
            return filePath
        }

        return approval.payload.toolName
    }
}

struct AIPluginExpandedSessionSummary: Equatable, Identifiable {
    let id: String
    let host: AIHost
    let title: String
    let subtitle: String
    let approvalCount: Int
    let approvalRequestID: String?
    let codexSurfaceID: String?
    let updatedAt: Date
    let inputTokenCount: Int?
    let outputTokenCount: Int?

    var hasAttention: Bool {
        approvalRequestID != nil || codexSurfaceID != nil
    }

    var hasTokenUsage: Bool {
        inputTokenCount != nil || outputTokenCount != nil
    }
}

struct CodexApprovalDetailPresentation: Equatable {
    let summaryText: String?
    let commandText: String

    init(surface: CodexActionableSurface) {
        let trimmedSummary = surface.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = surface.commandPreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedCommand.isEmpty == false {
            self.summaryText = trimmedSummary.isEmpty ? nil : trimmedSummary
            self.commandText = trimmedCommand
        } else {
            self.summaryText = nil
            self.commandText = trimmedSummary
        }
    }
}

enum CodexApprovalTextInputIndexPlacement: Equatable {
    case outsideField
    case insideFieldLeading
}

struct CodexApprovalTextInputPresentation: Equatable {
    let indexText: String
    let indexPlacement: CodexApprovalTextInputIndexPlacement
    let placeholder: String

    static func standalone(
        textInput: CodexSurfaceTextInput,
        index: Int
    ) -> CodexApprovalTextInputPresentation {
        CodexApprovalTextInputPresentation(
            indexText: "\(index).",
            indexPlacement: .insideFieldLeading,
            placeholder: textInput.title?.isEmpty == false
                ? (textInput.title ?? "")
                : "否，请告知 Codex 如何调整"
        )
    }

    static func feedback(
        textInput: CodexSurfaceTextInput,
        option: CodexSurfaceOption
    ) -> CodexApprovalTextInputPresentation {
        CodexApprovalTextInputPresentation(
            indexText: "\(option.index).",
            indexPlacement: .insideFieldLeading,
            placeholder: textInput.title?.isEmpty == false
                ? (textInput.title ?? option.title)
                : option.title
        )
    }
}

struct AIPluginExpandedSessionListPresentation: Equatable {
    let summaries: [AIPluginExpandedSessionSummary]

    var shouldRender: Bool {
        summaries.isEmpty == false
    }
}

struct AIPluginApprovalReviewState: Equatable {
    var isReviewingApprovals = false
    var selectedApprovalRequestID: String?

    mutating func beginReviewing(requestID: String) {
        isReviewingApprovals = true
        selectedApprovalRequestID = requestID
    }

    mutating func exitReviewing() {
        isReviewingApprovals = false
        selectedApprovalRequestID = nil
    }

    mutating func syncPendingRequestIDs(_ requestIDs: [String]) {
        guard isReviewingApprovals else {
            if requestIDs.isEmpty {
                selectedApprovalRequestID = nil
            }
            return
        }

        if let selectedApprovalRequestID,
           requestIDs.contains(selectedApprovalRequestID) {
            return
        }

        selectedApprovalRequestID = requestIDs.first
        if selectedApprovalRequestID == nil {
            isReviewingApprovals = false
        }
    }
}

struct AIPluginCodexSurfaceReviewState: Equatable {
    var selectedSurfaceID: String?

    mutating func sync(
        currentSurfaceID: String?,
        isReviewingApprovals: Bool,
        currentSelectionMatchesSurface: Bool
    ) {
        guard isReviewingApprovals == false else {
            return
        }

        guard let currentSurfaceID else {
            selectedSurfaceID = nil
            return
        }

        guard let selectedSurfaceID else {
            return
        }

        guard currentSelectionMatchesSurface == false else {
            return
        }

        self.selectedSurfaceID = selectedSurfaceID == currentSurfaceID ? selectedSurfaceID : currentSurfaceID
    }
}

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

struct AIPluginCompactMetrics {
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let sideFrameWidth: CGFloat
    let totalWidth: CGFloat
}

private enum AIPluginCompactLayout {
    static let outerPadding: CGFloat = 10
}

private enum AICompactTextMeasurer {
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
        outerPadding: CGFloat = AIPluginCompactLayout.outerPadding
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

private struct AIPluginCompactView<Plugin: AIPluginRendering>: View {
    @ObservedObject var plugin: Plugin
    let context: NotchContext
    let approvalNotice: AIPluginApprovalSneakNotice?
    let noticeLayout: AIPluginCompactApprovalNoticeLayout

    var body: some View {
        if let activity = plugin.currentCompactActivity,
           let metrics = plugin.compactMetrics(context: context) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    compactBrandCluster(activity)
                        .frame(width: metrics.sideFrameWidth, alignment: .leading)

                    Spacer(minLength: context.notchGeometry.compactSize.width)

                    HStack(spacing: 6) {
                        tokenChip(symbol: "arrow.up", value: activity.inputTokenCount)
                        tokenChip(symbol: "arrow.down", value: activity.outputTokenCount)
                    }
                    .frame(width: metrics.sideFrameWidth, alignment: .trailing)
                }
                .frame(height: context.notchGeometry.compactSize.height, alignment: .center)

                if let approvalNotice {
                    approvalNoticeRow(approvalNotice)
                }
            }
            .padding(.horizontal, AIPluginCompactLayout.outerPadding)
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
                Text("Idle")
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
                    color: hostColor(for: activity.host),
                    foreground: .white
                )
            }
        }
    }

    private func approvalNoticeRow(_ notice: AIPluginApprovalSneakNotice) -> some View {
        Text(notice.text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            .lineLimit(noticeLayout.lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: noticeLayout.height, alignment: noticeLayout.isSingleLine ? .center : .top)
    }

    private func tokenChip(symbol: String, value: Int?) -> some View {
        let marker = symbol == "arrow.up" ? "↑" : "↓"
        return Text("\(marker)\(plugin.formattedTokenCount(value))")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
    }
}

private struct AIPluginExpandedView<Plugin: AIPluginRendering>: View {
    @ObservedObject var plugin: Plugin
    @State private var approvalReviewState = AIPluginApprovalReviewState()
    @State private var codexSurfaceReviewState = AIPluginCodexSurfaceReviewState()
    @State private var codexApprovalInteractionState: CodexApprovalInteractionState?
    @State private var codexTextDraftSurfaceID: String?
    @State private var codexTextDraft = ""
    @State private var codexTextInputContentHeight: CGFloat = 0
    @State private var claudeFeedbackRequestID: String?
    @State private var claudeFeedbackText = ""
    @State private var claudeFeedbackContentHeight: CGFloat = 0

    private let codexTextInputFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private let claudeFeedbackFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                if let selectedApproval {
                    approvalDetailView(selectedApproval)
                } else if let selectedCodexSurface {
                    codexSurfaceDetailView(selectedCodexSurface)
                } else {
                    sessionListView
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncCurrentCodexSurfaceSelection()
        }
        .onChange(of: plugin.pendingApprovals.map(\.requestID)) { _, requestIDs in
            approvalReviewState.syncPendingRequestIDs(requestIDs)
            if let claudeFeedbackRequestID, requestIDs.contains(claudeFeedbackRequestID) == false {
                resetClaudeFeedback()
            }
        }
        .onChange(of: plugin.codexActionableSurface?.id) { _, surfaceID in
            if surfaceID == nil {
                codexSurfaceReviewState.selectedSurfaceID = nil
                codexApprovalInteractionState = nil
                codexTextDraftSurfaceID = nil
                codexTextDraft = ""
                codexTextInputContentHeight = 0
                return
            }

            syncCurrentCodexSurfaceSelection()
        }
    }

    private var selectedApproval: PendingApproval? {
        guard let selectedApprovalRequestID = approvalReviewState.selectedApprovalRequestID else {
            return nil
        }

        return plugin.pendingApprovals.first(where: { $0.requestID == selectedApprovalRequestID })
    }

    private var selectedCodexSurface: CodexActionableSurface? {
        guard let selectedSurfaceID = codexSurfaceReviewState.selectedSurfaceID else {
            return nil
        }

        return plugin.codexActionableSurface?.id == selectedSurfaceID
            ? plugin.codexActionableSurface
            : nil
    }

    private func syncCurrentCodexSurfaceSelection() {
        codexSurfaceReviewState.sync(
            currentSurfaceID: plugin.codexActionableSurface?.id,
            isReviewingApprovals: approvalReviewState.isReviewingApprovals,
            currentSelectionMatchesSurface: selectedCodexSurface != nil
        )
        codexApprovalInteractionState = nil
        codexTextDraftSurfaceID = nil
        codexTextDraft = ""
        codexTextInputContentHeight = 0
    }

    private var isClaudePlugin: Bool {
        plugin.id == "claude"
    }

    private var isCodexPlugin: Bool {
        plugin.id == "codex"
    }

    @ViewBuilder
    private var sessionListView: some View {
        if isClaudePlugin {
            claudeSessionListView
        } else if isCodexPlugin {
            codexSessionListView
        } else {
            genericSessionListView
        }
    }

    @ViewBuilder
    private var claudeSessionListView: some View {
        if sessionListPresentation.shouldRender {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plugin.expandedSessionSummaries) { summary in
                    claudeSessionRow(summary)
                }
            }
        }
    }

    @ViewBuilder
    private var codexSessionListView: some View {
        if sessionListPresentation.shouldRender {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plugin.expandedSessionSummaries) { summary in
                    codexSessionRow(summary)
                }
            }
        }
    }

    @ViewBuilder
    private var genericSessionListView: some View {
        if sessionListPresentation.shouldRender {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plugin.expandedSessionSummaries) { summary in
                    sessionRow(summary)
                }
            }
        }
    }

    private var sessionListPresentation: AIPluginExpandedSessionListPresentation {
        AIPluginExpandedSessionListPresentation(summaries: plugin.expandedSessionSummaries)
    }

    private func approvalDetailView(_ approval: PendingApproval) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            minimalBackButton
            approvalCard(approval)
        }
    }

    private func codexSurfaceDetailView(_ surface: CodexActionableSurface) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            minimalBackButton
            codexSurfaceCard(surface)
        }
        .background(
            CodexApprovalKeyMonitor(
                isEnabled: true,
                focusedTarget: codexApprovalInteractionState?.focusedTarget,
                onMoveUp: {
                    moveCodexApprovalFocusUp(surface: surface)
                },
                onMoveDown: {
                    moveCodexApprovalFocusDown(surface: surface)
                },
                onSubmit: {
                    submitCodexSurface(surface)
                }
            )
            .allowsHitTesting(false)
        )
        .onAppear {
            syncCodexApprovalInteraction(with: surface)
        }
        .onChange(of: surface) { _, updatedSurface in
            syncCodexApprovalInteraction(with: updatedSurface)
        }
    }

    private var minimalBackButton: some View {
        Button {
            exitDetail()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private func claudeSessionRow(_ summary: AIPluginExpandedSessionSummary) -> some View {
        let isInteractive = summary.approvalRequestID != nil

        return Button {
            if let approvalRequestID = summary.approvalRequestID {
                codexSurfaceReviewState.selectedSurfaceID = nil
                approvalReviewState.beginReviewing(requestID: approvalRequestID)
            }
        } label: {
            HStack(spacing: 10) {
                NotchPilotBrandIcon(glyph: .claude, size: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(summary.subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            summary.hasAttention
                                ? NotchPilotTheme.claude
                                : NotchPilotTheme.islandTextSecondary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInteractive == false)
        .opacity(isInteractive ? 1 : 0.92)
    }

    private func codexSessionRow(_ summary: AIPluginExpandedSessionSummary) -> some View {
        let isInteractive = summary.codexSurfaceID != nil

        return Button {
            if let codexSurfaceID = summary.codexSurfaceID {
                approvalReviewState.exitReviewing()
                codexSurfaceReviewState.selectedSurfaceID = codexSurfaceID
                codexApprovalInteractionState = nil
                codexTextInputContentHeight = 0
            }
        } label: {
            HStack(spacing: 10) {
                NotchPilotBrandIcon(glyph: .codex, size: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(summary.subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            summary.hasAttention
                                ? NotchPilotTheme.codex
                                : NotchPilotTheme.islandTextSecondary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInteractive == false)
        .opacity(isInteractive ? 1 : 0.92)
    }

    private func sessionRow(_ summary: AIPluginExpandedSessionSummary) -> some View {
        Button {
            if let approvalRequestID = summary.approvalRequestID {
                codexSurfaceReviewState.selectedSurfaceID = nil
                approvalReviewState.beginReviewing(requestID: approvalRequestID)
            } else if let codexSurfaceID = summary.codexSurfaceID {
                approvalReviewState.exitReviewing()
                codexSurfaceReviewState.selectedSurfaceID = codexSurfaceID
                codexApprovalInteractionState = nil
                codexTextInputContentHeight = 0
            }
        } label: {
            HStack(spacing: 10) {
                if let glyph = NotchPilotBrandGlyph(host: summary.host) {
                    NotchPilotBrandIcon(glyph: glyph, size: 20)
                } else {
                    NotchPilotIconTile(
                        systemName: plugin.iconSystemName,
                        accent: plugin.accentColor,
                        size: 20,
                        isActive: summary.hasAttention
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(summary.subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            summary.hasAttention
                                ? hostColor(for: summary.host).opacity(0.92)
                                : NotchPilotTheme.islandTextSecondary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(summary.hasAttention == false)
        .opacity(summary.hasAttention ? 1 : 0.88)
    }

    private func exitDetail() {
        approvalReviewState.exitReviewing()
        codexSurfaceReviewState.selectedSurfaceID = nil
        codexApprovalInteractionState = nil
        codexTextDraftSurfaceID = nil
        codexTextDraft = ""
        codexTextInputContentHeight = 0
    }

    private func codexSurfaceCard(_ surface: CodexActionableSurface) -> some View {
        codexApprovalPrimaryColumn(surface)
    }

    private func codexApprovalSummary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codexApprovalCommand(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            .lineLimit(4)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
    }

    private func codexApprovalPrimaryColumn(_ surface: CodexActionableSurface) -> some View {
        let presentation = CodexApprovalDetailPresentation(surface: surface)

        return VStack(alignment: .leading, spacing: 10) {
            if let summaryText = presentation.summaryText {
                codexApprovalSummary(summaryText)
            }

            codexApprovalCommand(presentation.commandText)
            codexSurfaceControls(surface)
            codexSurfaceButtons(surface)
        }
    }

    private func codexSurfaceButtons(_ surface: CodexActionableSurface) -> some View {
        let cancelFocused = codexApprovalInteractionState?.focusedTarget == .cancel
        let submitFocused = codexApprovalInteractionState?.focusedTarget == .submit

        return HStack(spacing: 10) {
            Spacer()

            Button {
                focusCodexApproval(.cancel, surface: surface)
                _ = plugin.performCodexAction(.cancel, surfaceID: surface.id)
            } label: {
                Text(surface.cancelButtonTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(cancelFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(cancelFocused ? 0.18 : 0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button {
                focusCodexApproval(.submit, surface: surface)
                submitCodexSurface(surface)
            } label: {
                Text(surface.primaryButtonTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        NotchPilotTheme.codex,
                                        NotchPilotTheme.codex.opacity(0.72),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(submitFocused ? 0.24 : 0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func codexSurfaceControls(_ surface: CodexActionableSurface) -> some View {
        if surface.options.isEmpty == false || surface.textInput != nil {
            VStack(alignment: .leading, spacing: 8) {
                let feedbackOptionID = CodexApprovalInteractionState.feedbackOptionID(for: surface)
                let standardOptions = surface.options.filter { $0.id != feedbackOptionID }
                let feedbackOption = feedbackOptionID.flatMap { optionID in
                    surface.options.first(where: { $0.id == optionID })
                }

                if standardOptions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(standardOptions) { option in
                            codexSurfaceOptionRow(option, surface: surface)
                        }
                    }
                }

                if let textInput = surface.textInput {
                    if let feedbackOption {
                        codexSurfaceFeedbackInput(textInput, option: feedbackOption, surface: surface)
                    } else {
                        codexSurfaceStandaloneTextInput(
                            textInput,
                            surface: surface,
                            index: surface.options.count + 1
                        )
                    }
                }
            }
        }
    }

    private func codexSurfaceOptionRow(_ option: CodexSurfaceOption, surface: CodexActionableSurface) -> some View {
        let isSelected = codexApprovalInteractionState?.isOptionSelected(option.id, in: surface) ?? option.isSelected

        return Button {
            activateCodexApprovalOption(option.id, surface: surface)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(option.index)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : NotchPilotTheme.islandTextSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(
                                isSelected
                                    ? NotchPilotTheme.codex.opacity(0.95)
                                    : Color.white.opacity(0.08)
                            )
                    )

                Text(option.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? NotchPilotTheme.islandTextPrimary : NotchPilotTheme.islandTextPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    NotchPilotTheme.codex.opacity(0.12),
                                    NotchPilotTheme.codex.opacity(0.04),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(0.03),
                                    Color.white.opacity(0.015),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? NotchPilotTheme.codex.opacity(0.2) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func codexSurfaceFeedbackInput(
        _ textInput: CodexSurfaceTextInput,
        option: CodexSurfaceOption,
        surface: CodexActionableSurface
    ) -> some View {
        let focusTarget = CodexApprovalFocusTarget.textInput(optionID: option.id)
        let isFocused = codexApprovalInteractionState?.focusedTarget == focusTarget
        let presentation = CodexApprovalTextInputPresentation.feedback(textInput: textInput, option: option)
        let sizing = CodexApprovalTextInputSizing(
            lineHeight: codexTextInputFont.lineHeight,
            verticalPadding: 12
        )
        let leadingInset: CGFloat = presentation.indexPlacement == .insideFieldLeading ? 28 : 0

        return ZStack(alignment: .topLeading) {
            if presentation.indexPlacement == .insideFieldLeading {
                Text(presentation.indexText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 10)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .topLeading) {
                CodexApprovalTextEditor(
                    text: codexTextBinding(for: surface),
                    isEditable: textInput.isEditable,
                    isFocused: isFocused,
                    font: codexTextInputFont,
                    onFocus: {
                        focusCodexApproval(focusTarget, surface: surface)
                    },
                    onSubmit: {
                        submitCodexSurface(surface)
                    },
                    onMoveUpBoundary: {
                        moveCodexApprovalFocusFromTextInput(towardStart: true, surface: surface)
                    },
                    onMoveDownBoundary: {
                        moveCodexApprovalFocusFromTextInput(towardStart: false, surface: surface)
                    },
                    onContentHeightChange: { contentHeight in
                        codexTextInputContentHeight = contentHeight
                    }
                )
                .padding(.leading, leadingInset)
                .frame(height: sizing.height(forContentHeight: codexTextInputContentHeight))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isFocused ? NotchPilotTheme.codex.opacity(0.48) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .disabled(textInput.isEditable == false)

                if isFocused == false,
                   currentCodexTextDraft(for: surface).isEmpty,
                   presentation.placeholder.isEmpty == false {
                    Text(presentation.placeholder)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.leading, 10 + leadingInset)
                        .padding(.trailing, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusCodexApproval(focusTarget, surface: surface)
        }
    }

    private func codexSurfaceStandaloneTextInput(
        _ textInput: CodexSurfaceTextInput,
        surface: CodexActionableSurface,
        index: Int
    ) -> some View {
        let focusTarget = CodexApprovalFocusTarget.textInput(optionID: nil)
        let isFocused = codexApprovalInteractionState?.focusedTarget == focusTarget
        let presentation = CodexApprovalTextInputPresentation.standalone(textInput: textInput, index: index)
        let sizing = CodexApprovalTextInputSizing(
            lineHeight: codexTextInputFont.lineHeight,
            verticalPadding: 12
        )
        let leadingInset: CGFloat = presentation.indexPlacement == .insideFieldLeading ? 28 : 0

        return ZStack(alignment: .topLeading) {
            if presentation.indexPlacement == .insideFieldLeading {
                Text(presentation.indexText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 10)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .topLeading) {
                CodexApprovalTextEditor(
                    text: codexTextBinding(for: surface),
                    isEditable: textInput.isEditable,
                    isFocused: isFocused,
                    font: codexTextInputFont,
                    onFocus: {
                        focusCodexApproval(focusTarget, surface: surface)
                    },
                    onSubmit: {
                        submitCodexSurface(surface)
                    },
                    onMoveUpBoundary: {
                        moveCodexApprovalFocusFromTextInput(towardStart: true, surface: surface)
                    },
                    onMoveDownBoundary: {
                        moveCodexApprovalFocusFromTextInput(towardStart: false, surface: surface)
                    },
                    onContentHeightChange: { contentHeight in
                        codexTextInputContentHeight = contentHeight
                    }
                )
                .padding(.leading, leadingInset)
                .frame(height: sizing.height(forContentHeight: codexTextInputContentHeight))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isFocused ? NotchPilotTheme.codex.opacity(0.48) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )

                if isFocused == false,
                   currentCodexTextDraft(for: surface).isEmpty,
                   presentation.placeholder.isEmpty == false {
                    Text(presentation.placeholder)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.leading, 10 + leadingInset)
                        .padding(.trailing, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            focusCodexApproval(focusTarget, surface: surface)
        }
    }

    private func codexTextBinding(for surface: CodexActionableSurface) -> Binding<String> {
        Binding(
            get: {
                currentCodexTextDraft(for: surface)
            },
            set: { newValue in
                codexTextDraftSurfaceID = surface.id
                codexTextDraft = newValue
            }
        )
    }

    private func approvalCard(_ approval: PendingApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            codexApprovalCommand(approvalCommandText(for: approval))
            approvalButtons(approval)
            if claudeFeedbackRequestID == approval.requestID {
                approvalFeedbackInput(approval)
            }
        }
    }

    private func approvalCommandText(for approval: PendingApproval) -> String {
        if let command = approval.payload.command, command.isEmpty == false {
            return command
        }

        if let networkApprovalContext = approval.networkApprovalContext {
            return networkApprovalSummary(networkApprovalContext)
        }

        if approval.payload.previewText.isEmpty == false {
            return approval.payload.previewText
        }

        if let filePath = approval.payload.filePath, filePath.isEmpty == false {
            return filePath
        }

        return approval.payload.toolName
    }

    private func approvalButtons(_ approval: PendingApproval) -> some View {
        let accent = hostColor(for: approval.host)
        let columns = [
            GridItem(.flexible(minimum: 120), spacing: 10),
            GridItem(.flexible(minimum: 120), spacing: 10),
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(approval.availableActions) { action in
                Button {
                    handleApprovalAction(action, approval: approval)
                } label: {
                    Text(action.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(foregroundColor(for: action.style))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(backgroundFill(for: action.style, accent: accent))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    borderColor(for: action.style, accent: accent),
                                    lineWidth: borderLineWidth(for: action.style)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func approvalFeedbackInput(_ approval: PendingApproval) -> some View {
        let sizing = CodexApprovalTextInputSizing(
            lineHeight: claudeFeedbackFont.lineHeight,
            verticalPadding: 12
        )

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                CodexApprovalTextEditor(
                    text: claudeFeedbackBinding(),
                    isEditable: true,
                    isFocused: claudeFeedbackRequestID == approval.requestID,
                    font: claudeFeedbackFont,
                    onFocus: {
                        claudeFeedbackRequestID = approval.requestID
                    },
                    onSubmit: {
                        submitClaudeFeedback(for: approval)
                    },
                    onMoveUpBoundary: {},
                    onMoveDownBoundary: {},
                    onContentHeightChange: { contentHeight in
                        claudeFeedbackContentHeight = contentHeight
                    }
                )
                .frame(height: sizing.height(forContentHeight: claudeFeedbackContentHeight))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NotchPilotTheme.claude.opacity(0.42), lineWidth: 1)
                )

                if claudeFeedbackText.isEmpty {
                    Text("Tell Claude what to change")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    submitClaudeFeedback(for: approval)
                } label: {
                    Text("Send")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(NotchPilotTheme.danger.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleApprovalAction(_ action: ApprovalAction, approval: PendingApproval) {
        switch action.payload {
        case .claudeDenyWithFeedback:
            claudeFeedbackRequestID = approval.requestID
            claudeFeedbackText = ""
            claudeFeedbackContentHeight = 0
        case .claude:
            resetClaudeFeedback()
            plugin.respond(to: approval.requestID, with: action)
        }
    }

    private func submitClaudeFeedback(for approval: PendingApproval) {
        let action = ApprovalAction(
            id: "claude-deny-feedback-submit",
            title: "No, tell Claude why",
            style: .destructive,
            payload: .claude(
                ApprovalDecision(
                    behavior: .deny,
                    feedbackText: claudeFeedbackText
                )
            )
        )
        resetClaudeFeedback()
        plugin.respond(to: approval.requestID, with: action)
    }

    private func claudeFeedbackBinding() -> Binding<String> {
        Binding(
            get: {
                claudeFeedbackText
            },
            set: { newValue in
                claudeFeedbackText = newValue
            }
        )
    }

    private func resetClaudeFeedback() {
        claudeFeedbackRequestID = nil
        claudeFeedbackText = ""
        claudeFeedbackContentHeight = 0
    }

    private func networkApprovalSummary(_ context: NetworkApprovalContext) -> String {
        let portSuffix = context.port.map { ":\($0)" } ?? ""
        return "\(context.protocolName.uppercased()) \(context.host)\(portSuffix)"
    }

    private func syncCodexApprovalInteraction(with surface: CodexActionableSurface) {
        if var existing = codexApprovalInteractionState {
            existing.sync(surface: surface)
            codexApprovalInteractionState = existing
        } else {
            codexApprovalInteractionState = CodexApprovalInteractionState(surface: surface)
        }
        syncCodexTextDraft(with: surface)
    }

    private func focusCodexApproval(_ target: CodexApprovalFocusTarget, surface: CodexActionableSurface) {
        var state = codexApprovalInteractionState ?? CodexApprovalInteractionState(surface: surface)
        _ = state.focus(target, surface: surface)
        codexApprovalInteractionState = state
    }

    private func activateCodexApprovalOption(_ optionID: String, surface: CodexActionableSurface) {
        var state = codexApprovalInteractionState ?? CodexApprovalInteractionState(surface: surface)
        let selectedOptionID = state.activateOption(optionID, surface: surface)
        codexApprovalInteractionState = state

        guard let selectedOptionID else {
            return
        }

        _ = plugin.selectCodexOption(selectedOptionID, surfaceID: surface.id)

        let feedbackOptionID = CodexApprovalInteractionState.feedbackOptionID(for: surface)
        if optionID != feedbackOptionID {
            submitCodexSurface(surface)
        }
    }

    private func moveCodexApprovalFocusUp(surface: CodexActionableSurface) {
        var state = codexApprovalInteractionState ?? CodexApprovalInteractionState(surface: surface)
        _ = state.moveUp(surface: surface)
        codexApprovalInteractionState = state
    }

    private func moveCodexApprovalFocusDown(surface: CodexActionableSurface) {
        var state = codexApprovalInteractionState ?? CodexApprovalInteractionState(surface: surface)
        _ = state.moveDown(surface: surface)
        codexApprovalInteractionState = state
    }

    private func moveCodexApprovalFocusFromTextInput(
        towardStart: Bool,
        surface: CodexActionableSurface
    ) {
        var state = codexApprovalInteractionState ?? CodexApprovalInteractionState(surface: surface)
        guard let focusedTarget = state.focusedTarget,
              case .textInput = focusedTarget
        else {
            if towardStart {
                _ = state.moveUp(surface: surface)
            } else {
                _ = state.moveDown(surface: surface)
            }
            codexApprovalInteractionState = state
            return
        }

        let nextTarget = state.adjacentTarget(
            from: focusedTarget,
            delta: towardStart ? -1 : 1,
            surface: surface
        )
        _ = state.focus(nextTarget, surface: surface)
        codexApprovalInteractionState = state
    }

    private func syncCodexApprovalStateToSurface(surface: CodexActionableSurface) {
        if let optionID = codexApprovalInteractionState?.selectedOptionIDToSync(in: surface),
           surface.options.first(where: { $0.id == optionID })?.isSelected != true {
            _ = plugin.selectCodexOption(optionID, surfaceID: surface.id)
        }

        if surface.textInput != nil {
            let draftText = currentCodexTextDraft(for: surface)
            if draftText != (surface.textInput?.text ?? "") {
                _ = plugin.updateCodexText(draftText, surfaceID: surface.id)
            }
        }
    }

    private func submitCodexSurface(_ surface: CodexActionableSurface) {
        let state = codexApprovalInteractionState ?? CodexApprovalInteractionState(surface: surface)

        if state.submitIntent(in: surface) == .cancel {
            _ = plugin.performCodexAction(.cancel, surfaceID: surface.id)
            return
        }

        syncCodexApprovalStateToSurface(surface: surface)
        _ = plugin.performCodexAction(.primary, surfaceID: surface.id)
    }

    private func syncCodexTextDraft(with surface: CodexActionableSurface) {
        guard codexTextDraftSurfaceID != surface.id else {
            return
        }

        codexTextDraftSurfaceID = surface.id
        codexTextDraft = surface.textInput?.text ?? ""
    }

    private func currentCodexTextDraft(for surface: CodexActionableSurface) -> String {
        if codexTextDraftSurfaceID == surface.id {
            return codexTextDraft
        }

        return surface.textInput?.text ?? ""
    }

    private func foregroundColor(for style: ApprovalActionStyle) -> Color {
        switch style {
        case .primary:
            return .white
        case .secondary, .destructive, .outline:
            return .white
        }
    }

    private func backgroundFill(for style: ApprovalActionStyle, accent: Color) -> Color {
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

    private func borderColor(for style: ApprovalActionStyle, accent: Color) -> Color {
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

    private func borderLineWidth(for style: ApprovalActionStyle) -> CGFloat {
        style == .primary ? 0 : 1
    }

}

private func hostColor(for host: AIHost) -> Color {
    NotchPilotTheme.brand(for: host)
}
