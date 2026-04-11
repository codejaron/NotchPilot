import AppKit
import Combine
import SwiftUI

@MainActor
public final class ClaudePlugin: AIPluginRendering {
    public let id = "claude"
    public let title = "Claude"
    public let iconSystemName = "sparkles"
    public let accentColor: Color = NotchPilotTheme.claude
    public let dockOrder = 100
    public let previewPriority: Int? = 100

    @Published public var isEnabled = true
    @Published public private(set) var sessions: [AISession] = []
    @Published public private(set) var pendingApprovals: [PendingApproval] = []
    @Published public private(set) var codexActionableSurface: CodexActionableSurface?
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
        codexActionableSurface = nil
        lastErrorMessage = nil
        bus = nil
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
                responders[requestID] = respond
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

        guard case let .claude(decision) = action.payload else {
            responder(Data("{}".utf8))
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
            responder(data)
        } catch {
            responder(Data("{}".utf8))
        }

        _ = runtime.resolvePendingApproval(requestID: requestID)
        syncState()
        dismissSneakPeek(for: requestID)
    }

    var currentCompactActivity: AIPluginCompactActivity? {
        if let approval = pendingApprovals.first {
            let matchingSession = sessions.first(where: { $0.id == approval.sessionID })
            return AIPluginCompactActivity(
                host: approval.host,
                label: "Approval",
                inputTokenCount: matchingSession?.inputTokenCount,
                outputTokenCount: matchingSession?.outputTokenCount,
                approvalCount: pendingApprovals.count,
                sessionTitle: matchingSession.flatMap(displayTitle(for:)),
                runtimeDurationText: nil
            )
        }

        guard let session = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first else {
            return nil
        }

        return AIPluginCompactActivity(
            host: session.host,
            label: session.activityLabel,
            inputTokenCount: session.inputTokenCount,
            outputTokenCount: session.outputTokenCount,
            approvalCount: 0,
            sessionTitle: displayTitle(for: session),
            runtimeDurationText: nil
        )
    }

    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] {
        let pendingApprovalsBySessionID = Dictionary(grouping: pendingApprovals, by: \.sessionID)

        return sessions
            .map { session in
                let sessionApprovals = pendingApprovalsBySessionID[session.id] ?? []
                let firstApproval = sessionApprovals.first
                return AIPluginExpandedSessionSummary(
                    id: session.id,
                    host: session.host,
                    title: expandedSessionTitle(for: session),
                    subtitle: expandedSessionSubtitle(for: session, approval: firstApproval),
                    approvalCount: sessionApprovals.count,
                    approvalRequestID: firstApproval?.requestID,
                    codexSurfaceID: nil,
                    updatedAt: session.updatedAt,
                    inputTokenCount: session.inputTokenCount,
                    outputTokenCount: session.outputTokenCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.hasAttention != rhs.hasAttention {
                    return lhs.hasAttention
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public func displayTitle(for session: AISession) -> String? {
        normalizedSessionTitle(session.sessionTitle)
    }

    public func expandedSessionTitle(for session: AISession) -> String {
        displayTitle(for: session) ?? hostDisplayName(for: session.host)
    }

    private func expandedSessionSubtitle(
        for session: AISession,
        approval: PendingApproval?
    ) -> String {
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

    private func syncState() {
        sessions = runtime.sessions
        pendingApprovals = runtime.pendingApprovals
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

    private func dismissSneakPeek(for requestID: String) {
        guard let sneakPeekID = sneakPeekIDs.removeValue(forKey: requestID) else {
            return
        }

        bus?.emit(.dismissSneakPeek(requestID: sneakPeekID, target: .allScreens))
    }

    private func normalizedSessionTitle(_ rawTitle: String?) -> String? {
        guard let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false
        else {
            return nil
        }

        return title
    }
}
