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
    private let encoder: HookResponseEncoder
    private let sessionScopedApprovalStore: SessionScopedRuleStoring
    private let settingsStore: SettingsStore
    private let nowProvider: @Sendable () -> Date
    private let sessionFocuser: any AISessionFocusing

    private weak var bus: EventBus?
    private var responders: [String: @Sendable (Data) -> Void] = [:]
    private var sneakPeekIDs: [String: UUID] = [:]
    private var settingsCancellables: Set<AnyCancellable> = []
    private var activityTracker = ClaudeSessionActivityTracker()

    public init(
        settingsStore: SettingsStore = .shared,
        permissionRuleStore: PermissionRuleWriting = PermissionRuleStore(),
        sessionScopedApprovalStore: SessionScopedRuleStoring = SessionScopedApprovalStore(),
        sessionFocuser: any AISessionFocusing = SystemAISessionFocuser(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.encoder = HookResponseEncoder(permissionRuleStore: permissionRuleStore)
        self.sessionScopedApprovalStore = sessionScopedApprovalStore
        self.sessionFocuser = sessionFocuser
        self.nowProvider = nowProvider
        settingsStore.$approvalSneakNotificationsEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handleApprovalSneakSettingChange(isEnabled: isEnabled)
            }
            .store(in: &settingsCancellables)
    }

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
        activityTracker.reset()
        bus = nil
    }

    public func handle(frame: BridgeFrame, respond: @escaping @Sendable (Data) -> Void) {
        guard frame.host == .claude else {
            respond(Data("{}".utf8))
            return
        }

        do {
            let envelope = try parser.parse(frame: frame)
            activityTracker.observe(
                sessionID: envelope.sessionID,
                eventType: envelope.eventType,
                at: nowProvider()
            )

            if envelope.eventType == .stop {
                sessionScopedApprovalStore.clearSession(envelope.sessionID)
            }

            if envelope.needsResponse,
               case let .permissionRequest(payload) = envelope.payload,
               sessionScopedApprovalStore.matches(sessionID: envelope.sessionID, payload: payload) {
                _ = runtime.handle(envelope: bypass(envelope: envelope))
                syncState()
                do {
                    let data = try encoder.encode(
                        decision: .allowOnce,
                        for: envelope.host,
                        eventType: envelope.eventType
                    )
                    respond(data)
                } catch {
                    respond(Data("{}".utf8))
                }
                return
            }

            let result = runtime.handle(envelope: envelope)
            syncState()

            switch result {
            case let .respondNow(data):
                respond(data)
            case let .awaitDecision(requestID):
                responders[requestID] = respond
                syncSneakPeek()
            }
        } catch {
            lastErrorMessage = "Failed to parse \(frame.host.rawValue) bridge event."
            respond(Data("{}".utf8))
        }
    }

    private func bypass(envelope: AIBridgeEnvelope) -> AIBridgeEnvelope {
        AIBridgeEnvelope(
            host: envelope.host,
            requestID: envelope.requestID,
            sessionID: envelope.sessionID,
            eventType: envelope.eventType,
            capabilities: envelope.capabilities,
            needsResponse: false,
            launchContext: envelope.launchContext,
            payload: envelope.payload
        )
    }

    public func handleDisconnect(requestID: String) {
        responders.removeValue(forKey: requestID)

        guard runtime.expirePendingApproval(requestID: requestID) != nil else {
            return
        }

        syncState()
        syncSneakPeek()
    }

    public func respond(to requestID: String, with action: ApprovalAction) {
        guard
            let approval = pendingApprovals.first(where: { $0.requestID == requestID }),
            let responder = responders.removeValue(forKey: requestID)
        else {
            return
        }

        let decision: ApprovalDecision
        switch action.payload {
        case let .claude(actionDecision):
            decision = actionDecision
        case .claudeDenyWithFeedback:
            decision = .denyOnce
        }

        if let sessionRule = decision.sessionRule {
            sessionScopedApprovalStore.addRule(sessionRule, sessionID: approval.sessionID)
        }

        do {
            let data = try encoder.encode(
                decision: decision,
                for: approval.host,
                eventType: approval.eventType ?? .permissionRequest
            )
            responder(data)
        } catch {
            responder(Data("{}".utf8))
        }

        _ = runtime.resolvePendingApproval(requestID: requestID)
        syncState()
        syncSneakPeek()
    }

    var approvalSneakNotificationsEnabled: Bool {
        settingsStore.approvalSneakNotificationsEnabled
    }

    var activitySneakPreviewsHidden: Bool {
        settingsStore.activitySneakPreviewsHidden
    }

    var currentCompactActivity: AIPluginCompactActivity? {
        if approvalSneakNotificationsEnabled, let approval = pendingApprovals.first {
            let matchingSession = sessions.first(where: { $0.id == approval.sessionID })
            return AIPluginCompactActivity(
                host: approval.host,
                label: "Approval",
                inputTokenCount: matchingSession?.inputTokenCount,
                outputTokenCount: matchingSession?.outputTokenCount,
                approvalCount: pendingApprovals.count,
                sessionTitle: matchingSession.flatMap(displayTitle(for:)),
                runtimeDurationText: runtimeDurationText(forSessionID: approval.sessionID)
            )
        }

        guard let session = compactPreviewSession() else {
            return nil
        }

        return AIPluginCompactActivity(
            host: session.host,
            label: session.activityLabel,
            inputTokenCount: session.inputTokenCount,
            outputTokenCount: session.outputTokenCount,
            approvalCount: 0,
            sessionTitle: displayTitle(for: session),
            runtimeDurationText: runtimeDurationText(forSessionID: session.id)
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
                    phase: expandedSessionPhase(for: session),
                    approvalCount: sessionApprovals.count,
                    approvalRequestID: firstApproval?.requestID,
                    codexSurfaceID: nil,
                    updatedAt: session.updatedAt,
                    inputTokenCount: session.inputTokenCount,
                    outputTokenCount: session.outputTokenCount,
                    runtimeDurationText: runtimeDurationText(forSessionID: session.id)
                )
            }
            .sorted { lhs, rhs in
                if lhs.hasAttention != rhs.hasAttention {
                    return lhs.hasAttention
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    @discardableResult
    public func activateSession(id: String) -> Bool {
        guard let session = sessions.first(where: { $0.id == id }) else {
            return false
        }

        return sessionFocuser.focus(
            context: session.launchContext ?? AISessionLaunchContext(),
            fallback: .host(.claude)
        )
    }

    private func runtimeDurationText(forSessionID sessionID: String) -> String? {
        guard let duration = activityTracker.duration(forSessionID: sessionID, now: nowProvider()) else {
            return nil
        }

        return AIRuntimeDurationFormatter.format(duration)
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

    private func expandedSessionPhase(for session: AISession) -> AIPluginSessionPhase {
        switch session.lastEventType {
        case .stop:
            return .completed
        case .sessionStart:
            return .connected
        default:
            return .working
        }
    }

    private func syncState() {
        sessions = runtime.sessions
        pendingApprovals = runtime.pendingApprovals
    }

    private func handleApprovalSneakSettingChange(isEnabled: Bool) {
        objectWillChange.send()
        syncSneakPeek(approvalSneakNotificationsEnabled: isEnabled)
    }

    private func presentSneakPeek(for requestID: String) {
        guard sneakPeekIDs[requestID] == nil else {
            return
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: 1000,
            target: .activeScreen,
            kind: .attention,
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

    private func syncSneakPeek() {
        syncSneakPeek(approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled)
    }

    private func syncSneakPeek(approvalSneakNotificationsEnabled: Bool) {
        let pendingRequestIDs = Set(pendingApprovals.map(\.requestID))

        for requestID in Array(sneakPeekIDs.keys)
        where approvalSneakNotificationsEnabled == false || pendingRequestIDs.contains(requestID) == false {
            dismissSneakPeek(for: requestID)
        }

        guard approvalSneakNotificationsEnabled else {
            return
        }

        for requestID in pendingApprovals.map(\.requestID) {
            presentSneakPeek(for: requestID)
        }
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

struct ClaudeSessionActivityTracker {
    private var firstActiveAt: [String: Date] = [:]
    private var lastActiveAt: [String: Date] = [:]
    private var lastEventType: [String: AIBridgeEventType] = [:]

    mutating func reset() {
        firstActiveAt.removeAll()
        lastActiveAt.removeAll()
        lastEventType.removeAll()
    }

    mutating func observe(sessionID: String, eventType: AIBridgeEventType, at date: Date) {
        let previousWasTerminal = (lastEventType[sessionID] == .stop)
        let nextIsActive = (eventType != .stop)

        if firstActiveAt[sessionID] == nil || (previousWasTerminal && nextIsActive) {
            firstActiveAt[sessionID] = date
        }

        if let existing = lastActiveAt[sessionID] {
            lastActiveAt[sessionID] = max(existing, date)
        } else {
            lastActiveAt[sessionID] = date
        }

        lastEventType[sessionID] = eventType
    }

    func duration(forSessionID sessionID: String, now: Date) -> TimeInterval? {
        guard let start = firstActiveAt[sessionID] else {
            return nil
        }

        let isTerminal = (lastEventType[sessionID] == .stop)
        let endedAt: Date = isTerminal ? (lastActiveAt[sessionID] ?? now) : now
        return max(0, endedAt.timeIntervalSince(start))
    }
}
