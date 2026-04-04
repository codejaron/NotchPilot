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
        guard let approval = pendingApprovals.first else {
            return nil
        }

        return AnyView(AIApprovalSneakPeekView(approval: approval))
    }

    public func sneakPeekWidth(context: NotchContext) -> CGFloat? {
        pendingApprovals.isEmpty ? nil : 420
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
                approvalCount: pendingApprovals.count
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
            approvalCount: 0
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

private struct AIApprovalSneakPeekView: View {
    let approval: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(hostLabel, systemImage: hostIconName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(hostColor.opacity(0.22)))

                Text(approval.payload.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Text(approval.payload.previewText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(2)

            Text("Hover to open the notch, then choose Allow or Deny.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var hostLabel: String {
        approval.host == .claude ? "CLAUDE" : "CODEX"
    }

    private var hostIconName: String {
        approval.host == .claude ? "sparkles" : "terminal"
    }

    private var hostColor: Color {
        approval.host == .claude ? .orange : .blue
    }
}

private struct AIExpandedView: View {
    @ObservedObject var plugin: AIAgentPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            pendingApprovalsSection
            sessionsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Control Tower")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Claude and Codex bridge activity surfaces here.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            }

            Spacer()

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
    }

    @ViewBuilder
    private var pendingApprovalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pending Approvals")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            if plugin.pendingApprovals.isEmpty {
                emptyCard("No approvals waiting.")
            } else {
                ForEach(plugin.pendingApprovals) { approval in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(approval.payload.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(approval.payload.previewText)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Button("Allow") { plugin.respond(to: approval.requestID, with: .allowOnce) }
                            Button("Deny") { plugin.respond(to: approval.requestID, with: .denyOnce) }
                            if approval.capabilities.supportsPersistentRules {
                                Button("Always Allow") { plugin.respond(to: approval.requestID, with: .persistAllowRule) }
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.white)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                }
            }
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            if plugin.sessions.isEmpty {
                emptyCard("No active bridge sessions.")
            } else {
                ForEach(plugin.sessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(session.host.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(session.id)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                            Spacer()
                            Text(session.activityLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }

                        HStack(spacing: 12) {
                            tokenLabel("↑", value: session.inputTokenCount)
                            tokenLabel("↓", value: session.outputTokenCount)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
                }
            }
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.6))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func tokenLabel(_ symbol: String, value: Int?) -> some View {
        Text("\(symbol) \(value.map(String.init) ?? "--")")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.58))
    }
}
