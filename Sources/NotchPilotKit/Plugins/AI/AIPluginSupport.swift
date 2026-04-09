import AppKit
import SwiftUI

@MainActor
protocol AIPluginRendering: NotchPlugin {
    var sessions: [AISession] { get }
    var pendingApprovals: [PendingApproval] { get }
    var codexActionableSurface: CodexActionableSurface? { get }
    var currentCompactActivity: AIPluginCompactActivity? { get }
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] { get }

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
        guard let metrics = compactMetrics(context: context) else {
            return nil
        }

        return NotchPluginPreview(
            width: metrics.totalWidth,
            view: AnyView(
                AIPluginCompactView(plugin: self, context: context)
            )
        )
    }

    public func contentView(context: NotchContext) -> AnyView {
        AnyView(AIPluginExpandedView(plugin: self))
    }

    func compactMetrics(context: NotchContext) -> AIPluginCompactMetrics? {
        guard let activity = currentCompactActivity else {
            return nil
        }

        let hostLabel = activity.host == .claude ? "Claude" : "Codex"
        let leftWidth =
            7
            + 6
            + AICompactTextMeasurer.width(
                hostLabel,
                font: .systemFont(ofSize: 10, weight: .semibold)
            )
            + 4
            + AICompactTextMeasurer.width(
                activity.label,
                font: .systemFont(ofSize: 11, weight: .semibold)
            )

        let rightWidth =
            tokenWidth(symbol: "↑", value: activity.inputTokenCount)
            + 6
            + tokenWidth(symbol: "↓", value: activity.outputTokenCount)
            + (activity.approvalCount > 0 ? 6 + approvalBadgeWidth(count: activity.approvalCount) : 0)

        let sideFrameWidth = max(leftWidth, rightWidth)
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

    var hasAttention: Bool {
        approvalRequestID != nil || codexSurfaceID != nil
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

        guard selectedSurfaceID == nil || currentSelectionMatchesSurface == false else {
            return
        }

        selectedSurfaceID = currentSurfaceID
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
}

private struct AIPluginCompactView<Plugin: AIPluginRendering>: View {
    @ObservedObject var plugin: Plugin
    let context: NotchContext

    var body: some View {
        if let activity = plugin.currentCompactActivity,
           let metrics = plugin.compactMetrics(context: context) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(hostColor(for: activity.host))
                        .frame(width: 7, height: 7)

                    Text(activity.host == .claude ? "Claude" : "Codex")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(activity.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: metrics.sideFrameWidth, alignment: .leading)

                Spacer(minLength: context.notchGeometry.compactSize.width)

                HStack(spacing: 6) {
                    tokenChip(symbol: "arrow.up", value: activity.inputTokenCount)
                    tokenChip(symbol: "arrow.down", value: activity.outputTokenCount)

                    if activity.approvalCount > 0 {
                        Text("\(activity.approvalCount)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.28)))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: metrics.sideFrameWidth, alignment: .trailing)
            }
            .padding(.horizontal, AIPluginCompactLayout.outerPadding)
            .frame(width: metrics.totalWidth, alignment: .center)
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

    private func tokenChip(symbol: String, value: Int?) -> some View {
        let marker = symbol == "arrow.up" ? "↑" : "↓"
        return Text("\(marker)\(plugin.formattedTokenCount(value))")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))
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

    private let codexTextInputFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
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

    private var sessionListView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(plugin.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                settingsButton
            }

            if plugin.expandedSessionSummaries.isEmpty {
                Text("Waiting for AI agent events…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(plugin.expandedSessionSummaries) { summary in
                        sessionRow(summary)
                    }
                }
            }
        }
    }

    private func approvalDetailView(_ approval: PendingApproval) -> some View {
        let session = plugin.sessions.first(where: { $0.id == approval.sessionID })

        return VStack(alignment: .leading, spacing: 14) {
            detailHeader(
                title: session.map(plugin.expandedSessionTitle(for:)) ?? plugin.hostDisplayName(for: approval.host),
                subtitle: approvalHeading(for: approval),
                host: approval.host
            )

            approvalCard(approval, session: session)
        }
    }

    private func codexSurfaceDetailView(_ surface: CodexActionableSurface) -> some View {
        let displayTitle = plugin.preferredCodexTitle(for: surface) ?? plugin.hostDisplayName(for: .codex)

        return VStack(alignment: .leading, spacing: 14) {
            detailHeader(
                title: displayTitle,
                subtitle: codexSurfaceHeading(for: surface),
                host: .codex
            )

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

    private func detailHeader(title: String, subtitle: String, host: AIHost) -> some View {
        HStack(spacing: 10) {
            Button {
                exitDetail()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Back")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)

            Circle()
                .fill(hostColor(for: host))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Spacer()

            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        } label: {
            Image(systemName: "gear")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(6)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(hostColor(for: summary.host))
                        .frame(width: 8, height: 8)

                    if summary.hasAttention {
                        Circle()
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: 5, height: 5)
                    } else {
                        Spacer()
                            .frame(width: 5, height: 5)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(summary.subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(summary.hasAttention ? .orange : .white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                if summary.hasAttention {
                    Text("\(summary.approvalCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(summary.hasAttention == false)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(surface.summary)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let previewText = surface.commandPreview,
               previewText.isEmpty == false {
                commandPreview(previewText, icon: "terminal")
            }

            codexSurfaceControls(surface)
            codexSurfaceButtons(surface)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func codexSurfaceButtons(_ surface: CodexActionableSurface) -> some View {
        let cancelFocused = codexApprovalInteractionState?.focusedTarget == .cancel
        let submitFocused = codexApprovalInteractionState?.focusedTarget == .submit

        return HStack(spacing: 14) {
            Spacer()

            Button {
                focusCodexApproval(.cancel, surface: surface)
                _ = plugin.performCodexAction(.cancel, surfaceID: surface.id)
            } label: {
                Text(surface.cancelButtonTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(cancelFocused ? .white : .white.opacity(0.62))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(cancelFocused ? Color.white.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)

            Button {
                focusCodexApproval(.submit, surface: surface)
                submitCodexSurface(surface)
            } label: {
                Text(surface.primaryButtonTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.9))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.95))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                submitFocused ? Color.black.opacity(0.45) : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func codexSurfaceControls(_ surface: CodexActionableSurface) -> some View {
        if surface.options.isEmpty == false || surface.textInput != nil {
            VStack(alignment: .leading, spacing: 10) {
                let feedbackOptionID = CodexApprovalInteractionState.feedbackOptionID(for: surface)
                let standardOptions = surface.options.filter { $0.id != feedbackOptionID }
                let feedbackOption = feedbackOptionID.flatMap { optionID in
                    surface.options.first(where: { $0.id == optionID })
                }

                if standardOptions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
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
            HStack(alignment: .top, spacing: 12) {
                Text("\(option.index).")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .black.opacity(0.75) : .white.opacity(0.45))
                    .frame(width: 20, alignment: .leading)

                Text(option.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                        Image(systemName: "arrow.down")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.35))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: isSelected ? 0 : 1)
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
        let placeholder = textInput.title?.isEmpty == false ? (textInput.title ?? option.title) : option.title
        let sizing = CodexApprovalTextInputSizing(
            lineHeight: codexTextInputFont.lineHeight,
            verticalPadding: 16
        )

        return HStack(alignment: .top, spacing: 12) {
            Text("\(option.index).")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 20, alignment: .leading)

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
                .frame(height: sizing.height(forContentHeight: codexTextInputContentHeight))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .disabled(textInput.isEditable == false)

                if isFocused == false,
                   codexTextDraft(for: surface).isEmpty,
                   placeholder.isEmpty == false {
                    Text(placeholder)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusCodexApproval(focusTarget, surface: surface)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codexSurfaceStandaloneTextInput(
        _ textInput: CodexSurfaceTextInput,
        surface: CodexActionableSurface,
        index: Int
    ) -> some View {
        let focusTarget = CodexApprovalFocusTarget.textInput(optionID: nil)
        let isFocused = codexApprovalInteractionState?.focusedTarget == focusTarget
        let placeholder = textInput.title?.isEmpty == false ? (textInput.title ?? "") : "否，请告知 Codex 如何调整"
        let sizing = CodexApprovalTextInputSizing(
            lineHeight: codexTextInputFont.lineHeight,
            verticalPadding: 16
        )

        return HStack(alignment: .top, spacing: 12) {
            Text("\(index).")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 20, alignment: .leading)

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
                .frame(height: sizing.height(forContentHeight: codexTextInputContentHeight))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

                if isFocused == false,
                   codexTextDraft(for: surface).isEmpty,
                   placeholder.isEmpty == false {
                    Text(placeholder)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                focusCodexApproval(focusTarget, surface: surface)
            }
        }
    }

    private func codexTextBinding(for surface: CodexActionableSurface) -> Binding<String> {
        Binding(
            get: {
                codexTextDraft(for: surface)
            },
            set: { newValue in
                codexTextDraftSurfaceID = surface.id
                codexTextDraft = newValue
            }
        )
    }

    private func approvalCard(_ approval: PendingApproval, session: AISession?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(hostColor(for: approval.host))
                    .frame(width: 8, height: 8)

                Text(approvalHeading(for: approval))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(approval.payload.toolName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let filePath = approval.payload.filePath {
                    Text(filePath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }

            approvalMetadata(approval, session: session)

            if let command = approval.payload.command {
                commandPreview(command, icon: "terminal")
            } else if let networkApprovalContext = approval.networkApprovalContext {
                commandPreview(networkApprovalSummary(networkApprovalContext), icon: "network")
            } else if approval.payload.previewText.isEmpty == false {
                commandPreview(
                    approval.payload.previewText,
                    icon: approval.payload.filePath == nil ? "text.alignleft" : "doc"
                )
            }

            if let diffContent = approval.payload.diffContent, diffContent.isEmpty == false {
                diffView(approval.payload)
            }

            approvalButtons(approval)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func approvalMetadata(_ approval: PendingApproval, session: AISession?) -> some View {
        let rows = approvalMetadataRows(for: approval, session: session)
        if rows.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.42))
                            .frame(width: 62, alignment: .leading)

                        Text(row.value)
                            .font(.system(size: 11, weight: .medium, design: row.monospaced ? .monospaced : .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private func commandPreview(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))

            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func diffView(_ payload: ApprovalPayload) -> some View {
        let preview = AIPluginApprovalDiffPreview(payload: payload)
        let visibleLines = Array(preview.lines.prefix(8))
        let hiddenLineCount = max(preview.lines.count - visibleLines.count, 0)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 0) {
                    Text(line.lineNumber)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 32, alignment: .trailing)
                        .padding(.trailing, 8)

                    Text(line.prefix)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(diffForegroundColor(for: line.kind))
                        .frame(width: 14, alignment: .leading)

                    Text(line.text)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(diffForegroundColor(for: line.kind))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(diffBackgroundColor(for: line.kind, isSyntaxHighlighted: preview.isSyntaxHighlighted))
            }

            if hiddenLineCount > 0 {
                Text("+\(hiddenLineCount) more lines")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func approvalButtons(_ approval: PendingApproval) -> some View {
        let columns = [
            GridItem(.flexible(minimum: 120), spacing: 10),
            GridItem(.flexible(minimum: 120), spacing: 10),
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(approval.availableActions) { action in
                Button {
                    plugin.respond(to: approval.requestID, with: action)
                } label: {
                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(foregroundColor(for: action.style))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(backgroundFill(for: action.style))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(borderColor(for: action.style), lineWidth: borderLineWidth(for: action.style))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func codexSurfaceHeading(for surface: CodexActionableSurface) -> String {
        surface.options.isEmpty && surface.textInput == nil
            ? "Codex Approval"
            : "Codex Approval Mirror"
    }

    private func approvalHeading(for approval: PendingApproval) -> String {
        switch approval.approvalKind {
        case .toolRequest:
            return "Tool Approval"
        case .commandExecution:
            return "Command Approval"
        case .fileChange:
            return "File Change Approval"
        case .networkAccess:
            return "Network Approval"
        }
    }

    private func approvalMetadataRows(for approval: PendingApproval, session: AISession?) -> [ApprovalMetadataRow] {
        var rows: [ApprovalMetadataRow] = []

        if let reason = approval.reason, reason.isEmpty == false {
            rows.append(ApprovalMetadataRow(label: "Reason", value: reason, monospaced: false))
        }
        if let cwd = approval.cwd, cwd.isEmpty == false {
            rows.append(ApprovalMetadataRow(label: "CWD", value: cwd, monospaced: true))
        }
        if let grantRoot = approval.grantRoot, grantRoot.isEmpty == false {
            rows.append(ApprovalMetadataRow(label: "Root", value: grantRoot, monospaced: true))
        }
        if let threadTitle = session.flatMap({ plugin.displayTitle(for: $0) }) {
            rows.append(ApprovalMetadataRow(label: "Thread", value: threadTitle, monospaced: false))
        }

        return rows
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
            let draftText = codexTextDraft(for: surface)
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

    private func codexTextDraft(for surface: CodexActionableSurface) -> String {
        if codexTextDraftSurfaceID == surface.id {
            return codexTextDraft
        }

        return surface.textInput?.text ?? ""
    }

    private func foregroundColor(for style: ApprovalActionStyle) -> Color {
        switch style {
        case .primary:
            return .black
        case .secondary, .destructive, .outline:
            return .white
        }
    }

    private func backgroundFill(for style: ApprovalActionStyle) -> Color {
        switch style {
        case .primary:
            return Color.white.opacity(0.92)
        case .secondary:
            return Color.blue.opacity(0.28)
        case .destructive:
            return Color.red.opacity(0.28)
        case .outline:
            return Color.white.opacity(0.08)
        }
    }

    private func borderColor(for style: ApprovalActionStyle) -> Color {
        switch style {
        case .primary:
            return .clear
        case .secondary:
            return Color.blue.opacity(0.32)
        case .destructive:
            return Color.red.opacity(0.32)
        case .outline:
            return Color.white.opacity(0.16)
        }
    }

    private func borderLineWidth(for style: ApprovalActionStyle) -> CGFloat {
        style == .primary ? 0 : 1
    }

    private func diffForegroundColor(for kind: AIPluginApprovalDiffLineKind) -> Color {
        switch kind {
        case .metadata:
            return .white.opacity(0.45)
        case .removal:
            return Color(red: 1.0, green: 0.45, blue: 0.45)
        case .addition:
            return Color(red: 0.45, green: 0.9, blue: 0.45)
        case .context:
            return .white.opacity(0.88)
        }
    }

    private func diffBackgroundColor(for kind: AIPluginApprovalDiffLineKind, isSyntaxHighlighted: Bool) -> Color {
        guard isSyntaxHighlighted else {
            return .clear
        }

        switch kind {
        case .metadata, .context:
            return .clear
        case .removal:
            return Color(red: 0.6, green: 0.15, blue: 0.15).opacity(0.25)
        case .addition:
            return Color(red: 0.15, green: 0.5, blue: 0.15).opacity(0.25)
        }
    }
}

private struct ApprovalMetadataRow: Equatable {
    let label: String
    let value: String
    let monospaced: Bool
}

private func hostColor(for host: AIHost) -> Color {
    host == .claude ? .orange : .blue
}
