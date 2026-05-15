import AppKit
import Combine
import SwiftUI

@MainActor
public final class ClaudePlugin: AIPluginRendering {
    private enum SneakPeekKey {
        static let activity = "claude-activity"
    }

    public let id = "claude"
    public let title = "Claude"
    public let iconSystemName = "sparkles"
    public let accentColor: Color = NotchPilotTheme.claude
    public let dockOrder = 100
    public let previewPriority: Int? = 100

    private static let claudeSessionActivityExpiry: TimeInterval = 24 * 60 * 60

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
    private let transcriptReader: any ClaudeTranscriptReading

    private weak var bus: EventBus?
    private var responders: [String: @Sendable (Data) -> Void] = [:]
    private var sneakPeekIDs: [String: UUID] = [:]
    private var settingsCancellables: Set<AnyCancellable> = []
    private var activityTracker = ClaudeSessionActivityTracker(activityExpiry: ClaudePlugin.claudeSessionActivityExpiry)

    public init(
        settingsStore: SettingsStore = .shared,
        permissionRuleStore: PermissionRuleWriting = PermissionRuleStore(),
        sessionScopedApprovalStore: SessionScopedRuleStoring = SessionScopedApprovalStore(),
        sessionFocuser: any AISessionFocusing = SystemAISessionFocuser(),
        transcriptReader: any ClaudeTranscriptReading = ClaudeTranscriptReader(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.encoder = HookResponseEncoder(permissionRuleStore: permissionRuleStore)
        self.sessionScopedApprovalStore = sessionScopedApprovalStore
        self.sessionFocuser = sessionFocuser
        self.transcriptReader = transcriptReader
        self.nowProvider = nowProvider
        self.isEnabled = Self.aggregateEnabled(
            claude: settingsStore.claudePluginEnabled,
            devin: settingsStore.devinPluginEnabled
        )

        // The Claude plugin owns two distinct hosts (Claude Code and Devin
        // Local). Either toggle being on means the plugin still has work to do;
        // we publish a single aggregate `isEnabled` for UI compatibility but
        // route incoming frames against the per-host flag inside `handle()`.
        //
        // We deliberately read the *publisher's emitted value* instead of
        // re-reading `settingsStore.<flag>` inside the sink: `@Published` fires
        // in `willSet`, so a synchronous re-read would observe the stale value
        // and the aggregate would lag one tick behind.
        settingsStore.$claudePluginEnabled
            .removeDuplicates()
            .sink { [weak self] claudeEnabled in
                guard let self else { return }
                self.applyAggregateEnabled(
                    claude: claudeEnabled,
                    devin: self.settingsStore.devinPluginEnabled
                )
            }
            .store(in: &settingsCancellables)

        settingsStore.$devinPluginEnabled
            .removeDuplicates()
            .sink { [weak self] devinEnabled in
                guard let self else { return }
                self.applyAggregateEnabled(
                    claude: self.settingsStore.claudePluginEnabled,
                    devin: devinEnabled
                )
            }
            .store(in: &settingsCancellables)

        settingsStore.$approvalSneakNotificationsEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handleApprovalSneakSettingChange(isEnabled: isEnabled)
            }
            .store(in: &settingsCancellables)

        settingsStore.$activitySneakPreviewsHidden
            .removeDuplicates()
            .sink { [weak self] isHidden in
                self?.handleActivitySneakSettingChange(isHidden: isHidden)
            }
            .store(in: &settingsCancellables)

        settingsStore.$interfaceLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.syncSneakPeek()
            }
            .store(in: &settingsCancellables)
    }

    public func activate(bus: EventBus) {
        guard isEnabled else {
            return
        }

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
        let reader = transcriptReader
        Task { await reader.reset() }
        bus = nil
    }

    public func handle(frame: BridgeFrame, respond: @escaping @Sendable (Data) -> Void) {
        // Devin Local reuses the Claude Code hook protocol (payload shape,
        // response schema, permission rule format). The bridge re-tags those
        // frames as `.devin` when the ancestor process is a Devin CLI; both
        // hosts are routed through this plugin and differentiated only at the
        // display layer (and by their separate enable toggles below).
        guard frame.host.isClaudeFamily else {
            respond(Data("{}".utf8))
            return
        }

        guard isEnabled(forHost: frame.host) else {
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
                expirePendingApprovals(forSessionID: envelope.sessionID)
            }

            if envelope.needsResponse,
               case let .permissionRequest(payload) = envelope.payload,
               sessionScopedApprovalStore.matches(sessionID: envelope.sessionID, payload: payload) {
                _ = runtime.handle(envelope: bypass(envelope: envelope))
                syncState()
                syncSneakPeek()
                scheduleTranscriptUsageRefresh(for: envelope)
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

            _ = resolveExternallyHandledApprovals(for: envelope)
            let result = runtime.handle(envelope: envelope)
            syncState()
            syncSneakPeek()
            scheduleTranscriptUsageRefresh(for: envelope)

            switch result {
            case let .respondNow(data):
                respond(data)
                if envelope.eventType == .stop {
                    SoundManager.shared.play(.taskComplete)
                }
            case let .awaitDecision(requestID):
                responders[requestID] = respond
                SoundManager.shared.play(.inputRequired)
            }
        } catch {
            lastErrorMessage = "Failed to parse \(frame.host.rawValue) bridge event."
            respond(Data("{}".utf8))
        }
    }

    private func scheduleTranscriptUsageRefresh(for envelope: AIBridgeEnvelope) {
        guard let transcriptPath = envelope.transcriptPath else {
            return
        }

        let sessionID = envelope.sessionID
        let reader = transcriptReader

        Task { [weak self] in
            guard let usage = await reader.usage(forSessionID: sessionID, transcriptPath: transcriptPath) else {
                return
            }

            await MainActor.run {
                guard let self else { return }
                let didChange = self.runtime.updateTokenCounts(
                    sessionID: sessionID,
                    inputTokenCount: usage.contextInputTokens,
                    outputTokenCount: usage.totalOutputTokens
                )
                if didChange {
                    self.syncState()
                    self.syncSneakPeek()
                }
            }
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

    @discardableResult
    private func resolveExternallyHandledApprovals(for envelope: AIBridgeEnvelope) -> Bool {
        guard isExternalApprovalCompletionEvent(envelope.eventType),
              let observedToolUse = ClaudeObservedToolUse(payload: envelope.payload)
        else {
            return false
        }

        let sessionApprovals = runtime.pendingApprovals.filter { approval in
            approval.sessionID == envelope.sessionID
        }

        var requestIDs = sessionApprovals
            .filter { observedToolUse.matches($0.payload) }
            .map(\.requestID)

        if requestIDs.isEmpty,
           let observedName = observedToolUse.toolName {
            let sameToolApprovals = sessionApprovals
                .filter { $0.payload.toolName == observedName }
            if sameToolApprovals.count == 1 {
                requestIDs = sameToolApprovals.map(\.requestID)
            }
        }

        guard requestIDs.isEmpty == false else {
            return false
        }

        for requestID in requestIDs {
            if let responder = responders.removeValue(forKey: requestID) {
                responder(Data("{}".utf8))
            }
            _ = runtime.resolvePendingApproval(requestID: requestID)
        }

        return true
    }

    private func expirePendingApprovals(forSessionID sessionID: String) {
        let staleRequestIDs = runtime.pendingApprovals
            .filter { $0.sessionID == sessionID }
            .map(\.requestID)

        guard staleRequestIDs.isEmpty == false else {
            return
        }

        for requestID in staleRequestIDs {
            if let responder = responders.removeValue(forKey: requestID) {
                responder(Data("{}".utf8))
            }
            _ = runtime.expirePendingApproval(requestID: requestID)
        }
    }

    private func isExternalApprovalCompletionEvent(_ eventType: AIBridgeEventType) -> Bool {
        switch eventType {
        case .preToolUse, .postToolUse:
            return true
        case .permissionRequest, .sessionStart, .stop, .userPromptSubmit, .unknown:
            return false
        }
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
        guard isEnabled else {
            return nil
        }

        if approvalSneakNotificationsEnabled, let approval = pendingApprovals.first {
            let matchingSession = sessions.first(where: { $0.id == approval.sessionID })
            return AIPluginCompactActivity(
                host: approval.host,
                label: "Action Needed",
                inputTokenCount: matchingSession?.inputTokenCount,
                outputTokenCount: matchingSession?.outputTokenCount,
                approvalCount: 0,
                sessionTitle: matchingSession.flatMap(displayTitle(for:)),
                runtimeDurationText: runtimeDurationText(forSessionID: approval.sessionID)
            )
        }

        guard activitySneakPreviewsHidden == false else {
            return nil
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
                    approvalCount: 0,
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
            fallback: .host(session.host)
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
        if approval != nil {
            return "Action Needed"
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
        pendingApprovals = runtime.pendingApprovals
        sessions = activityTracker.visibleSessions(
            from: runtime.sessions,
            pendingApprovals: pendingApprovals,
            now: nowProvider()
        )
    }

    private func handleApprovalSneakSettingChange(isEnabled: Bool) {
        objectWillChange.send()
        syncSneakPeek(
            approvalSneakNotificationsEnabled: isEnabled,
            activitySneakPreviewsHidden: activitySneakPreviewsHidden
        )
    }

    private func handleActivitySneakSettingChange(isHidden: Bool) {
        objectWillChange.send()
        syncSneakPeek(
            approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
            activitySneakPreviewsHidden: isHidden
        )
    }

    private static func aggregateEnabled(claude: Bool, devin: Bool) -> Bool {
        claude || devin
    }

    /// Per-host enable check used inside `handle()`. Returns `false` for any
    /// non-Claude-family host as a safety net even though `handle()` already
    /// rejects them earlier. Reading directly from the settings store is safe
    /// here because `handle()` is invoked from the socket layer well after any
    /// `@Published` willSet has settled.
    private func isEnabled(forHost host: AIHost) -> Bool {
        switch host {
        case .claude:
            return settingsStore.claudePluginEnabled
        case .devin:
            return settingsStore.devinPluginEnabled
        case .codex:
            return false
        }
    }

    private func applyAggregateEnabled(claude: Bool, devin: Bool) {
        let aggregate = Self.aggregateEnabled(claude: claude, devin: devin)
        if aggregate != isEnabled {
            isEnabled = aggregate
        }
        syncSneakPeek()
        objectWillChange.send()
    }

    private func presentSneakPeek(for requestID: String, kind: SneakPeekRequestKind) {
        guard sneakPeekIDs[requestID] == nil else {
            return
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: SneakPeekRequestPriority.ai,
            target: .activeScreen,
            kind: kind,
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
        syncSneakPeek(
            approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
            activitySneakPreviewsHidden: activitySneakPreviewsHidden
        )
    }

    private func syncSneakPeek(
        approvalSneakNotificationsEnabled: Bool,
        activitySneakPreviewsHidden: Bool
    ) {
        let pendingRequestIDs = Set(pendingApprovals.map(\.requestID))
        let shouldShowApprovals = isEnabled
            && approvalSneakNotificationsEnabled
            && pendingRequestIDs.isEmpty == false
        let shouldShowActivity = isEnabled
            && shouldShowApprovals == false
            && activitySneakPreviewsHidden == false
            && compactPreviewSession() != nil
        let desiredRequestIDs: Set<String>

        if shouldShowApprovals {
            desiredRequestIDs = pendingRequestIDs
        } else if shouldShowActivity {
            desiredRequestIDs = [SneakPeekKey.activity]
        } else {
            desiredRequestIDs = []
        }

        for requestID in Array(sneakPeekIDs.keys)
        where desiredRequestIDs.contains(requestID) == false {
            dismissSneakPeek(for: requestID)
        }

        if shouldShowApprovals {
            for requestID in pendingApprovals.map(\.requestID) {
                presentSneakPeek(for: requestID, kind: .attention)
            }
        } else if shouldShowActivity {
            presentSneakPeek(for: SneakPeekKey.activity, kind: .activity)
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
    private let activityExpiry: TimeInterval
    private var firstActiveAt: [String: Date] = [:]
    private var lastActiveAt: [String: Date] = [:]
    private var lastEventType: [String: AIBridgeEventType] = [:]

    init(activityExpiry: TimeInterval = 24 * 60 * 60) {
        self.activityExpiry = activityExpiry
    }

    mutating func reset() {
        firstActiveAt.removeAll()
        lastActiveAt.removeAll()
        lastEventType.removeAll()
    }

    mutating func observe(sessionID: String, eventType: AIBridgeEventType, at date: Date) {
        let previousWasTerminal = (lastEventType[sessionID] == .stop)
        let nextIsActive = eventType.marksClaudeSessionActivity

        if nextIsActive {
            if firstActiveAt[sessionID] == nil || previousWasTerminal {
                firstActiveAt[sessionID] = date
            }
            updateLastActiveAt(sessionID: sessionID, date: date)
        } else if eventType == .stop, firstActiveAt[sessionID] != nil {
            updateLastActiveAt(sessionID: sessionID, date: date)
        }

        lastEventType[sessionID] = eventType
    }

    func visibleSessions(
        from sessions: [AISession],
        pendingApprovals: [PendingApproval],
        now: Date
    ) -> [AISession] {
        let pendingSessionIDs = Set(pendingApprovals.map(\.sessionID))
        let cutoff = now.addingTimeInterval(-activityExpiry)

        return sessions.filter { session in
            if pendingSessionIDs.contains(session.id) {
                return true
            }

            guard firstActiveAt[session.id] != nil,
                  let lastActiveAt = lastActiveAt[session.id]
            else {
                return false
            }

            return lastActiveAt >= cutoff
        }
    }

    func duration(forSessionID sessionID: String, now: Date) -> TimeInterval? {
        guard let start = firstActiveAt[sessionID] else {
            return nil
        }

        let isTerminal = (lastEventType[sessionID] == .stop)
        let endedAt: Date = isTerminal ? (lastActiveAt[sessionID] ?? now) : now
        return max(0, endedAt.timeIntervalSince(start))
    }

    private mutating func updateLastActiveAt(sessionID: String, date: Date) {
        if let existing = lastActiveAt[sessionID] {
            lastActiveAt[sessionID] = max(existing, date)
        } else {
            lastActiveAt[sessionID] = date
        }
    }
}

private extension AIBridgeEventType {
    var marksClaudeSessionActivity: Bool {
        switch self {
        case .permissionRequest, .preToolUse, .postToolUse, .userPromptSubmit, .unknown:
            return true
        case .sessionStart, .stop:
            return false
        }
    }
}

private struct ClaudeObservedToolUse {
    let toolName: String?
    let command: String?
    let filePath: String?
    let webFetchURL: String?

    init?(payload: AIBridgePayload) {
        guard case let .generic(values) = payload else {
            return nil
        }

        self.toolName = Self.firstNonEmptyValue(in: values, keys: [
            "tool_name",
            "tool.name",
            "request.tool",
        ])
        self.command = Self.firstNonEmptyValue(in: values, keys: [
            "tool_input.command",
            "tool.input.command",
            "command",
            "request.command",
        ])
        self.filePath = Self.firstNonEmptyValue(in: values, keys: [
            "tool_input.file_path",
            "tool_input.filePath",
            "tool.input.file_path",
            "tool.input.filePath",
            "file_path",
            "filePath",
        ])
        self.webFetchURL = Self.firstNonEmptyValue(in: values, keys: [
            "tool_input.url",
            "tool.input.url",
            "url",
        ])
    }

    func matches(_ payload: ApprovalPayload) -> Bool {
        if let toolName, payload.toolName != toolName {
            return false
        }

        if let command {
            return Self.fuzzyEquals(payload.command, command)
                || Self.fuzzyEquals(payload.previewText, command)
        }

        if let filePath {
            return Self.fuzzyEquals(payload.filePath, filePath)
                || Self.fuzzyEquals(payload.previewText, filePath)
        }

        if let webFetchURL {
            return Self.fuzzyEquals(payload.webFetchURL, webFetchURL)
                || Self.fuzzyEquals(payload.previewText, webFetchURL)
        }

        return toolName != nil
    }

    private static func fuzzyEquals(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else {
            return false
        }
        if lhs == rhs {
            return true
        }
        let trimmedLHS = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRHS = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLHS == trimmedRHS && trimmedRHS.isEmpty == false
    }

    private static func firstNonEmptyValue(in values: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.isEmpty == false {
                return value
            }
        }
        return nil
    }
}
