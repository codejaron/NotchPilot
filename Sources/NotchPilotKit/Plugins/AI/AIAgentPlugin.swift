import AppKit
import Combine
import SwiftUI

@MainActor
public final class AIAgentPlugin: NotchPlugin {
    public let id = "ai"
    public let name = "AI Agents"
    public let iconSystemName = "sparkles.rectangle.stack"
    public let priority = 1000

    @Published public var isEnabled = true
    @Published public private(set) var sessions: [AISession] = []
    @Published public private(set) var pendingApprovals: [PendingApproval] = []
    @Published public private(set) var lastErrorMessage: String?

    private let runtime = AIAgentRuntime()
    private let parser = HookEventParser()
    private let encoder = HookResponseEncoder()
    private let settingsStore: SettingsStore
    private let codexMonitor: CodexDesktopMonitor

    private weak var bus: EventBus?
    private var responders: [String: ApprovalResponder] = [:]
    private var sneakPeekIDs: [String: UUID] = [:]

    public init(
        settingsStore: SettingsStore = .shared,
        codexMonitor: CodexDesktopMonitor = CodexDesktopMonitor()
    ) {
        self.settingsStore = settingsStore
        self.codexMonitor = codexMonitor
    }

    public func activate(bus: EventBus) {
        self.bus = bus
        codexMonitor.onReducerOutput = { [weak self] output in
            Task { @MainActor [weak self] in
                self?.handleCodexReducerOutput(output)
            }
        }
        codexMonitor.onApprovalRequest = { [weak self] approval, responder in
            Task { @MainActor [weak self] in
                self?.handleCodexApprovalRequest(approval, responder: responder)
            }
        }
        codexMonitor.onConnectionStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleCodexConnectionStateChange(state)
            }
        }
        codexMonitor.start()
    }

    public func deactivate() {
        codexMonitor.stop()
        codexMonitor.onReducerOutput = nil
        codexMonitor.onApprovalRequest = nil
        codexMonitor.onConnectionStateChanged = nil
        responders.removeAll()
        sneakPeekIDs.removeAll()
        sessions = []
        pendingApprovals = []
        bus = nil
    }

    public func compactView(context: NotchContext) -> AnyView? {
        AnyView(AICompactView(plugin: self, context: context))
    }

    public func compactWidth(context: NotchContext) -> CGFloat? {
        guard let metrics = compactMetrics(context: context) else {
            return nil
        }

        return metrics.totalWidth
    }

    public func sneakPeekView(context: NotchContext) -> AnyView? {
        guard pendingApprovals.isEmpty == false else {
            return nil
        }

        return AnyView(AIApprovalBadgeView(count: pendingApprovals.count))
    }

    public func sneakPeekWidth(context: NotchContext) -> CGFloat? {
        pendingApprovals.isEmpty ? nil : 280
    }

    public func expandedView(context: NotchContext) -> AnyView {
        AnyView(AIExpandedView(plugin: self))
    }

    public func handle(frame: BridgeFrame, respond: @escaping @Sendable (Data) -> Void) {
        guard frame.host == .claude else {
            respond(Data("{}".utf8))
            return
        }

        do {
            let envelope = try parser.parse(frame: frame)
            let result = runtime.handle(envelope: envelope)
            syncState()

            switch result {
            case let .respondNow(data):
                respond(data)
            case let .awaitDecision(requestID):
                responders[requestID] = .claude(respond)
                presentSneakPeek(for: requestID)
            }
        } catch {
            lastErrorMessage = "Failed to parse \(frame.host.rawValue) bridge event."
            respond(Data("{}".utf8))
        }
    }

    public func handleDisconnect(requestID: String) {
        responders.removeValue(forKey: requestID)

        guard runtime.expirePendingApproval(requestID: requestID) != nil else {
            return
        }

        syncState()
        dismissSneakPeek(for: requestID)
    }

    public func respond(to requestID: String, with decision: ApprovalDecision) {
        guard let approval = pendingApprovals.first(where: { $0.requestID == requestID }) else {
            return
        }

        let action = approval.availableActions.first(where: { $0.legacyClaudeDecision == decision })
            ?? ApprovalAction(
                id: "claude-fallback-\(decision)",
                title: "",
                style: .primary,
                payload: .claude(decision)
            )
        respond(to: requestID, with: action)
    }

    public func respond(to requestID: String, with action: ApprovalAction) {
        guard
            let approval = pendingApprovals.first(where: { $0.requestID == requestID }),
            let responder = responders.removeValue(forKey: requestID)
        else {
            return
        }

        switch responder {
        case let .claude(send):
            guard case let .claude(decision) = action.payload else {
                send(Data("{}".utf8))
                return
            }

            let effectiveDecision: ApprovalDecision
            if decision == .persistAllowRule && !approval.capabilities.supportsPersistentRules {
                effectiveDecision = .allowOnce
            } else {
                effectiveDecision = decision
            }

            do {
                let data = try encoder.encode(
                    decision: effectiveDecision,
                    for: approval.host,
                    eventType: approval.eventType ?? .permissionRequest
                )
                send(data)
            } catch {
                send(Data("{}".utf8))
            }
        case let .codex(send):
            send(action)
        }

        _ = runtime.resolvePendingApproval(requestID: requestID)
        syncState()
        dismissSneakPeek(for: requestID)
    }

    private func handleCodexReducerOutput(_ output: CodexDesktopReducerOutput) {
        let effects: [AIAgentRuntime.RuntimeEffect]

        switch output {
        case let .sessionUpsert(session):
            effects = runtime.apply(event: .sessionUpsert(session))
        case let .approvalRequested(approval):
            effects = runtime.apply(event: .approvalRequested(approval))
        case let .approvalResolved(requestID):
            effects = runtime.apply(event: .approvalResolved(requestID: requestID))
        }

        syncState()
        applyRuntimeEffects(effects)
    }

    private func handleCodexApprovalRequest(
        _ approval: PendingApproval,
        responder: @escaping CodexDesktopMonitor.ApprovalResponder
    ) {
        responders[approval.requestID] = .codex(responder)
        let effects = runtime.apply(event: .approvalRequested(approval))
        syncState()
        applyRuntimeEffects(effects)
    }

    private func handleCodexConnectionStateChange(_ state: CodexDesktopConnectionState) {
        settingsStore.updateCodexDesktopConnection(state)

        guard state.status != .connected, state.status != .connecting else {
            return
        }

        let effects = runtime.apply(event: .expireApprovals(host: .codex))
        syncState()
        applyRuntimeEffects(effects)
    }

    private func applyRuntimeEffects(_ effects: [AIAgentRuntime.RuntimeEffect]) {
        for effect in effects {
            switch effect {
            case let .approvalRequested(requestID):
                presentSneakPeek(for: requestID)
            case let .approvalDismissed(requestID):
                responders.removeValue(forKey: requestID)
                dismissSneakPeek(for: requestID)
            }
        }
    }

    private func presentSneakPeek(for requestID: String) {
        guard sneakPeekIDs[requestID] == nil else {
            return
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: 1000,
            target: .activeScreen,
            isInteractive: true,
            autoDismissAfter: nil
        )
        sneakPeekIDs[requestID] = request.id
        bus?.emit(.sneakPeekRequested(request))
    }

    private enum ApprovalResponder {
        case claude(@Sendable (Data) -> Void)
        case codex(CodexDesktopMonitor.ApprovalResponder)
    }

    private func syncState() {
        sessions = runtime.sessions
        pendingApprovals = runtime.pendingApprovals
    }

    private func dismissSneakPeek(for requestID: String) {
        guard let sneakPeekID = sneakPeekIDs.removeValue(forKey: requestID) else {
            return
        }

        bus?.emit(.dismissSneakPeek(requestID: sneakPeekID, target: .allScreens))
    }

    var currentCompactActivity: AICompactActivity? {
        if let approval = pendingApprovals.first {
            let matchingSession = sessions.first(where: { $0.id == approval.sessionID })
            return AICompactActivity(
                host: approval.host,
                label: "Approval",
                inputTokenCount: matchingSession?.inputTokenCount,
                outputTokenCount: matchingSession?.outputTokenCount,
                approvalCount: pendingApprovals.count,
                sessionTitle: matchingSession?.sessionTitle
            )
        }

        guard let session = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first else {
            return nil
        }

        return AICompactActivity(
            host: session.host,
            label: session.activityLabel,
            inputTokenCount: session.inputTokenCount,
            outputTokenCount: session.outputTokenCount,
            approvalCount: 0,
            sessionTitle: session.sessionTitle
        )
    }

    func compactMetrics(context: NotchContext) -> AICompactMetrics? {
        guard let activity = currentCompactActivity else {
            return nil
        }

        let hostLabel = activity.host == .claude ? "Claude" : "Codex"
        let leftWidth =
            7
            + 6
            + CompactTextMeasurer.width(
                hostLabel,
                font: .systemFont(ofSize: 10, weight: .semibold)
            )
            + 4
            + CompactTextMeasurer.width(
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
            AICompactLayout.outerPadding * 2
            + context.notchGeometry.compactSize.width
            + sideFrameWidth * 2

        return AICompactMetrics(
            leftWidth: leftWidth,
            rightWidth: rightWidth,
            sideFrameWidth: sideFrameWidth,
            totalWidth: totalWidth
        )
    }

    var expandedSessionSummaries: [AIExpandedSessionSummary] {
        let pendingApprovalsBySessionID = Dictionary(grouping: pendingApprovals, by: \.sessionID)

        return sessions
            .map { session in
                let sessionApprovals = pendingApprovalsBySessionID[session.id] ?? []
                let firstApproval = sessionApprovals.first
                return AIExpandedSessionSummary(
                    id: session.id,
                    host: session.host,
                    title: expandedSessionTitle(for: session),
                    subtitle: expandedSessionSubtitle(for: session, approval: firstApproval),
                    approvalCount: sessionApprovals.count,
                    approvalRequestID: firstApproval?.requestID,
                    updatedAt: session.updatedAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.hasPendingApproval != rhs.hasPendingApproval {
                    return lhs.hasPendingApproval
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func expandedSessionTitle(for session: AISession) -> String {
        guard let sessionTitle = session.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              sessionTitle.isEmpty == false
        else {
            return hostDisplayName(for: session.host)
        }

        return sessionTitle
    }

    func expandedSessionSubtitle(for session: AISession, approval: PendingApproval?) -> String {
        if let approval {
            if approval.approvalKind == .networkAccess {
                return "Network Access"
            }
            if approval.payload.toolName.isEmpty == false {
                return approval.payload.toolName
            }
        }

        return session.activityLabel
    }

    func hostDisplayName(for host: AIHost) -> String {
        host == .claude ? "Claude Code" : "OpenAI Codex"
    }

    private func tokenWidth(symbol: String, value: Int?) -> CGFloat {
        CompactTextMeasurer.width(
            "\(symbol)\(formattedTokenCount(value))",
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
    }

    private func approvalBadgeWidth(count: Int) -> CGFloat {
        CompactTextMeasurer.width(
            "\(count)",
            font: .systemFont(ofSize: 10, weight: .semibold)
        ) + 10
    }

    fileprivate func formattedTokenCount(_ value: Int?) -> String {
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

struct AICompactActivity: Equatable {
    let host: AIHost
    let label: String
    let inputTokenCount: Int?
    let outputTokenCount: Int?
    let approvalCount: Int
    let sessionTitle: String?
}

struct AIExpandedSessionSummary: Equatable, Identifiable {
    let id: String
    let host: AIHost
    let title: String
    let subtitle: String
    let approvalCount: Int
    let approvalRequestID: String?
    let updatedAt: Date

    var hasPendingApproval: Bool {
        approvalRequestID != nil
    }
}

struct AIApprovalReviewState: Equatable {
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

private struct ApprovalMetadataRow: Equatable {
    let label: String
    let value: String
    let monospaced: Bool
}

enum ApprovalDiffLineKind: Equatable {
    case metadata
    case removal
    case addition
    case context
}

struct ApprovalDiffLinePresentation: Equatable {
    let lineNumber: String
    let prefix: String
    let text: String
    let kind: ApprovalDiffLineKind
}

struct ApprovalDiffPreview: Equatable {
    let lines: [ApprovalDiffLinePresentation]
    let isSyntaxHighlighted: Bool

    private init(lines: [ApprovalDiffLinePresentation], isSyntaxHighlighted: Bool) {
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

    private static func parsePlainContent(_ lines: [String]) -> [ApprovalDiffLinePresentation] {
        lines.enumerated().map { index, line in
            ApprovalDiffLinePresentation(
                lineNumber: "\(index + 1)",
                prefix: " ",
                text: line,
                kind: .context
            )
        }
    }

    private static func parseUnifiedDiff(_ lines: [String]) -> [ApprovalDiffLinePresentation] {
        var oldLine = 1
        var newLine = 1
        var result: [ApprovalDiffLinePresentation] = []

        for rawLine in lines {
            if rawLine.hasPrefix("@@") || rawLine.hasPrefix("diff ") || rawLine.hasPrefix("---") || rawLine.hasPrefix("+++") {
                result.append(
                    ApprovalDiffLinePresentation(
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
                    ApprovalDiffLinePresentation(
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
                    ApprovalDiffLinePresentation(
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
                ApprovalDiffLinePresentation(
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

    private static func buildLineDiff(from oldLines: [String], to newLines: [String]) -> [ApprovalDiffLinePresentation] {
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
        var result: [ApprovalDiffLinePresentation] = []

        while oldIndex < oldCount && newIndex < newCount {
            if oldLines[oldIndex] == newLines[newIndex] {
                result.append(
                    ApprovalDiffLinePresentation(
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
                    ApprovalDiffLinePresentation(
                        lineNumber: "\(oldIndex + 1)",
                        prefix: "-",
                        text: oldLines[oldIndex],
                        kind: .removal
                    )
                )
                oldIndex += 1
            } else {
                result.append(
                    ApprovalDiffLinePresentation(
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
                ApprovalDiffLinePresentation(
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
                ApprovalDiffLinePresentation(
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

private struct AICompactView: View {
    @ObservedObject var plugin: AIAgentPlugin
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
            .padding(.horizontal, AICompactLayout.outerPadding)
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
        return Text("\(marker)\(tokenText(for: value))")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))
    }

    private func tokenText(for value: Int?) -> String {
        plugin.formattedTokenCount(value)
    }

    private func hostColor(for host: AIHost) -> Color {
        host == .claude ? .orange : .blue
    }
}

private enum AICompactLayout {
    static let outerPadding: CGFloat = 10
}

struct AICompactMetrics {
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let sideFrameWidth: CGFloat
    let totalWidth: CGFloat
}

private enum CompactTextMeasurer {
    static func width(_ text: String, font: NSFont) -> CGFloat {
        guard text.isEmpty == false else {
            return 0
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let rawWidth = (text as NSString).size(withAttributes: attributes).width
        return ceil(rawWidth)
    }
}

private struct AIApprovalBadgeView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            Text("\(count) approval\(count == 1 ? "" : "s") waiting")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Click to review")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 10)
    }
}

private struct AIExpandedView: View {
    @ObservedObject var plugin: AIAgentPlugin
    @State private var approvalReviewState = AIApprovalReviewState()

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedApproval {
                    approvalDetailView(selectedApproval)
                } else {
                    sessionListView
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: plugin.pendingApprovals.map(\.requestID)) { _, requestIDs in
            approvalReviewState.syncPendingRequestIDs(requestIDs)
        }
    }

    private var selectedApproval: PendingApproval? {
        guard let selectedApprovalRequestID = approvalReviewState.selectedApprovalRequestID else {
            return nil
        }

        return plugin.pendingApprovals.first(where: { $0.requestID == selectedApprovalRequestID })
    }

    private var sessionListView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("AI Agents")
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
            HStack(spacing: 10) {
                Button {
                    approvalReviewState.exitReviewing()
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
                    .fill(hostColor(for: approval.host))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.map(plugin.expandedSessionTitle(for:)) ?? plugin.hostDisplayName(for: approval.host))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(approvalHeading(for: approval))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }

                Spacer()

                settingsButton
            }

            approvalCard(approval)
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

    private func sessionRow(_ summary: AIExpandedSessionSummary) -> some View {
        Button {
            guard let approvalRequestID = summary.approvalRequestID else {
                return
            }
            approvalReviewState.beginReviewing(requestID: approvalRequestID)
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(hostColor(for: summary.host))
                        .frame(width: 8, height: 8)

                    if summary.hasPendingApproval {
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
                        .foregroundStyle(summary.hasPendingApproval ? .orange : .white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                if summary.hasPendingApproval {
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
        .disabled(summary.hasPendingApproval == false)
    }

    private func approvalCard(_ approval: PendingApproval) -> some View {
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

            approvalMetadata(approval)

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
    private func approvalMetadata(_ approval: PendingApproval) -> some View {
        let rows = approvalMetadataRows(for: approval)
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
        let preview = ApprovalDiffPreview(payload: payload)
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
                approvalActionButton(action) {
                    plugin.respond(to: approval.requestID, with: action)
                }
            }
        }
    }

    private func approvalActionButton(_ actionModel: ApprovalAction, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(actionModel.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(foregroundColor(for: actionModel.style))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill(for: actionModel.style))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor(for: actionModel.style), lineWidth: borderLineWidth(for: actionModel.style))
            )
        }
        .buttonStyle(.plain)
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

    private func approvalMetadataRows(for approval: PendingApproval) -> [ApprovalMetadataRow] {
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
        if let threadID = approval.threadID, threadID.isEmpty == false {
            rows.append(ApprovalMetadataRow(label: "Thread", value: threadID, monospaced: true))
        }

        return rows
    }

    private func networkApprovalSummary(_ context: NetworkApprovalContext) -> String {
        let portSuffix = context.port.map { ":\($0)" } ?? ""
        return "\(context.protocolName.uppercased()) \(context.host)\(portSuffix)"
    }

    private func foregroundColor(for style: ApprovalActionStyle) -> Color {
        switch style {
        case .primary:
            return .black
        case .secondary:
            return .white
        case .destructive:
            return .white
        case .outline:
            return .white.opacity(0.82)
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

    private func diffForegroundColor(for kind: ApprovalDiffLineKind) -> Color {
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

    private func diffBackgroundColor(for kind: ApprovalDiffLineKind, isSyntaxHighlighted: Bool) -> Color {
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

    private func hostColor(for host: AIHost) -> Color {
        host == .claude ? .orange : .blue
    }
}
