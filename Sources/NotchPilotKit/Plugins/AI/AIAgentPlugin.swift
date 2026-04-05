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

    private weak var bus: EventBus?
    private var responders: [String: @Sendable (Data) -> Void] = [:]
    private var sneakPeekIDs: [String: UUID] = [:]

    public init() {}

    public func activate(bus: EventBus) {
        self.bus = bus
    }

    public func deactivate() {
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
        do {
            let envelope = try parser.parse(frame: frame)
            let result = runtime.handle(envelope: envelope)
            syncState()

            switch result {
            case let .respondNow(data):
                respond(data)
            case let .awaitDecision(requestID):
                responders[requestID] = respond
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
        guard
            let approval = pendingApprovals.first(where: { $0.requestID == requestID }),
            let responder = responders.removeValue(forKey: requestID)
        else {
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
                eventType: approval.eventType
            )
            responder(data)
        } catch {
            responder(Data("{}".utf8))
        }

        _ = runtime.resolvePendingApproval(requestID: requestID)
        syncState()
        dismissSneakPeek(for: requestID)
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
        if let approval, approval.payload.toolName.isEmpty == false {
            return approval.payload.toolName
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
    @State private var selectedApprovalRequestID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedApproval {
                approvalDetailView(selectedApproval)
            } else {
                sessionListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: plugin.pendingApprovals.map(\.requestID)) { _, requestIDs in
            if let selectedApprovalRequestID, requestIDs.contains(selectedApprovalRequestID) == false {
                self.selectedApprovalRequestID = nil
            }
        }
    }

    private var selectedApproval: PendingApproval? {
        guard let selectedApprovalRequestID else {
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
                    selectedApprovalRequestID = nil
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.map(plugin.expandedSessionTitle(for:)) ?? plugin.hostDisplayName(for: approval.host))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(approval.payload.toolName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            selectedApprovalRequestID = approvalRequestID
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: approval.host == .claude ? "sparkles" : "terminal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(approval.host == .claude ? .orange : .blue)

                Text(approval.payload.toolName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()
            }

            if let command = approval.payload.command {
                previewBlock(text: command, icon: "terminal")
            } else if let filePath = approval.payload.filePath {
                previewBlock(text: filePath, icon: "doc")
            } else {
                previewBlock(text: approval.payload.previewText, icon: nil)
            }

            if let diffContent = approval.payload.diffContent, diffContent.isEmpty == false {
                Text(diffContent)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(5)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04)))
            }

            HStack(spacing: 8) {
                Button("Deny") { plugin.respond(to: approval.requestID, with: .denyOnce) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                // Claude exposes interactive approval hooks here. Codex currently
                // only uses deny-only PreToolUse handling, so it does not surface
                // Allow / Always Allow actions in the notch UI.
                if approval.host == .claude {
                    Button("Allow") { plugin.respond(to: approval.requestID, with: .allowOnce) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    if approval.capabilities.supportsPersistentRules {
                        Button("Always Allow") { plugin.respond(to: approval.requestID, with: .persistAllowRule) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func previewBlock(text: String, icon: String?) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
    }

    private func hostColor(for host: AIHost) -> Color {
        host == .claude ? .orange : .blue
    }
}
