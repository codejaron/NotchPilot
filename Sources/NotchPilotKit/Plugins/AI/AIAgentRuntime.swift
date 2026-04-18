import Foundation

public struct AISession: Equatable, Sendable, Identifiable {
    public let id: String
    public let host: AIHost
    public var lastEventType: AIBridgeEventType
    public var activityLabel: String
    public var inputTokenCount: Int?
    public var outputTokenCount: Int?
    public var updatedAt: Date
    public var sessionTitle: String?
    public var launchContext: AISessionLaunchContext?

    public init(
        id: String,
        host: AIHost,
        lastEventType: AIBridgeEventType,
        activityLabel: String,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        updatedAt: Date = Date(),
        sessionTitle: String? = nil,
        launchContext: AISessionLaunchContext? = nil
    ) {
        self.id = id
        self.host = host
        self.lastEventType = lastEventType
        self.activityLabel = activityLabel
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.updatedAt = updatedAt
        self.sessionTitle = sessionTitle
        self.launchContext = launchContext?.isEmpty == true ? nil : launchContext
    }
}

public enum ApprovalStatus: String, Equatable, Sendable {
    case pending
    case resolved
    case expired
}

public struct PendingApproval: Equatable, Sendable, Identifiable {
    public var id: String { requestID }

    public let requestID: String
    public let sessionID: String
    public let host: AIHost
    public let approvalKind: ApprovalKind
    public let eventType: AIBridgeEventType?
    public let payload: ApprovalPayload
    public let capabilities: AIBridgeCapabilities
    public let availableActions: [ApprovalAction]
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let reason: String?
    public let cwd: String?
    public let grantRoot: String?
    public let networkApprovalContext: NetworkApprovalContext?
    public var status: ApprovalStatus
    public let createdAt: Date

    public init(
        requestID: String,
        sessionID: String,
        host: AIHost,
        approvalKind: ApprovalKind,
        eventType: AIBridgeEventType? = nil,
        payload: ApprovalPayload,
        capabilities: AIBridgeCapabilities,
        availableActions: [ApprovalAction],
        threadID: String? = nil,
        turnID: String? = nil,
        itemID: String? = nil,
        reason: String? = nil,
        cwd: String? = nil,
        grantRoot: String? = nil,
        networkApprovalContext: NetworkApprovalContext? = nil,
        status: ApprovalStatus,
        createdAt: Date = Date()
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.host = host
        self.approvalKind = approvalKind
        self.eventType = eventType
        self.payload = payload
        self.capabilities = capabilities
        self.availableActions = availableActions
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.reason = reason
        self.cwd = cwd
        self.grantRoot = grantRoot
        self.networkApprovalContext = networkApprovalContext
        self.status = status
        self.createdAt = createdAt
    }
}

public enum AIRealtimeEvent: Equatable {
    case sessionUpsert(AISession)
    case approvalRequested(PendingApproval)
    case approvalResolved(requestID: String)
    case expireApprovals(host: AIHost)
}

public final class AIAgentRuntime {
    public enum HandleResult: Equatable {
        case respondNow(Data)
        case awaitDecision(requestID: String)
    }

    public enum RuntimeEffect: Equatable {
        case approvalRequested(requestID: String)
        case approvalDismissed(requestID: String)
    }

    public private(set) var sessions: [AISession] = []
    public private(set) var pendingApprovals: [PendingApproval] = []

    public init() {}

    @discardableResult
    public func handle(envelope: AIBridgeEnvelope) -> HandleResult {
        refreshSession(
            id: envelope.sessionID,
            host: envelope.host,
            eventType: envelope.eventType,
            launchContext: envelope.launchContext,
            payload: envelope.payload
        )

        guard envelope.needsResponse else {
            return .respondNow(Data("{}".utf8))
        }

        guard case let .permissionRequest(payload) = envelope.payload else {
            return .respondNow(Data("{}".utf8))
        }

        let approval = PendingApproval(
            requestID: envelope.requestID,
            sessionID: envelope.sessionID,
            host: envelope.host,
            approvalKind: .toolRequest,
            eventType: envelope.eventType,
            payload: payload,
            capabilities: envelope.capabilities,
            availableActions: ApprovalAction.claudeActions(
                toolKind: payload.toolKind,
                toolName: payload.toolName,
                bashCommandPrefix: payload.bashCommandPrefix,
                webFetchDomain: payload.webFetchDomain,
                mcpServer: payload.mcpServer,
                mcpTool: payload.mcpTool
            ),
            status: .pending
        )

        _ = apply(event: .approvalRequested(approval))
        return .awaitDecision(requestID: envelope.requestID)
    }

    @discardableResult
    public func apply(event: AIRealtimeEvent) -> [RuntimeEffect] {
        switch event {
        case let .sessionUpsert(session):
            upsertSession(session)
            return []
        case let .approvalRequested(approval):
            pendingApprovals.removeAll(where: { $0.requestID == approval.requestID })
            pendingApprovals.append(approval)
            pendingApprovals.sort { $0.createdAt < $1.createdAt }
            return [.approvalRequested(requestID: approval.requestID)]
        case let .approvalResolved(requestID):
            guard resolvePendingApproval(requestID: requestID) != nil else {
                return []
            }
            return [.approvalDismissed(requestID: requestID)]
        case let .expireApprovals(host):
            let requestIDs = pendingApprovals
                .filter { $0.host == host }
                .map(\.requestID)
            pendingApprovals.removeAll(where: { $0.host == host })
            return requestIDs.map { .approvalDismissed(requestID: $0) }
        }
    }

    @discardableResult
    public func resolvePendingApproval(requestID: String) -> PendingApproval? {
        mutatePendingApproval(requestID: requestID, newStatus: .resolved)
    }

    @discardableResult
    public func expirePendingApproval(requestID: String) -> PendingApproval? {
        mutatePendingApproval(requestID: requestID, newStatus: .expired)
    }

    private func upsertSession(_ session: AISession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            var merged = sessions[index]
            merged.lastEventType = session.lastEventType
            merged.activityLabel = session.activityLabel
            if session.host == .codex {
                merged.inputTokenCount = session.inputTokenCount
                merged.outputTokenCount = session.outputTokenCount
            } else {
                if let inputTokenCount = session.inputTokenCount {
                    merged.inputTokenCount = inputTokenCount
                }
                if let outputTokenCount = session.outputTokenCount {
                    merged.outputTokenCount = outputTokenCount
                }
            }
            if let sessionTitle = session.sessionTitle, sessionTitle.isEmpty == false {
                if merged.sessionTitle?.isEmpty != false {
                    merged.sessionTitle = sessionTitle
                }
            }
            if merged.launchContext == nil,
               let launchContext = session.launchContext {
                merged.launchContext = launchContext
            }
            merged.updatedAt = Date()
            sessions[index] = merged
            sessions.sort { $0.updatedAt > $1.updatedAt }
            return
        }

        sessions.append(session)
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func refreshSession(
        id: String,
        host: AIHost,
        eventType: AIBridgeEventType,
        launchContext: AISessionLaunchContext?,
        payload: AIBridgePayload
    ) {
        let activity = SessionActivity(eventType: eventType, payload: payload)
        let sessionTitle = extractSessionTitle(from: payload, eventType: eventType)

        upsertSession(
            AISession(
                id: id,
                host: host,
                lastEventType: eventType,
                activityLabel: activity.label,
                inputTokenCount: activity.inputTokenCount,
                outputTokenCount: activity.outputTokenCount,
                sessionTitle: sessionTitle,
                launchContext: launchContext
            )
        )
    }

    private func extractSessionTitle(from payload: AIBridgePayload, eventType: AIBridgeEventType) -> String? {
        guard eventType == .userPromptSubmit else {
            return nil
        }

        guard case let .generic(values) = payload,
              let prompt = values["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              prompt.isEmpty == false
        else {
            return nil
        }

        let limit = 30
        guard prompt.count > limit else {
            return prompt
        }

        return String(prompt.prefix(limit)) + "…"
    }

    private func mutatePendingApproval(requestID: String, newStatus: ApprovalStatus) -> PendingApproval? {
        guard let index = pendingApprovals.firstIndex(where: { $0.requestID == requestID }) else {
            return nil
        }

        var approval = pendingApprovals.remove(at: index)
        approval.status = newStatus
        return approval
    }
}

private struct SessionActivity {
    let label: String
    let inputTokenCount: Int?
    let outputTokenCount: Int?

    init(eventType: AIBridgeEventType, payload: AIBridgePayload) {
        switch payload {
        case .permissionRequest:
            label = "Waiting Approval"
            inputTokenCount = nil
            outputTokenCount = nil
        case let .generic(values):
            label = SessionActivity.resolveLabel(eventType: eventType, values: values)
            inputTokenCount = SessionActivity.resolveCount(
                in: values,
                keys: [
                    "input_tokens",
                    "inputTokens",
                    "usage.input_tokens",
                    "token_usage.input_tokens",
                    "tokenUsage.inputTokens",
                    "tokens.input",
                    "prompt_tokens",
                    "promptTokens",
                ]
            )
            outputTokenCount = SessionActivity.resolveCount(
                in: values,
                keys: [
                    "output_tokens",
                    "outputTokens",
                    "usage.output_tokens",
                    "token_usage.output_tokens",
                    "tokenUsage.outputTokens",
                    "tokens.output",
                    "completion_tokens",
                    "completionTokens",
                ]
            )
        }
    }

    private static func resolveLabel(eventType: AIBridgeEventType, values: [String: String]) -> String {
        if let explicit = firstNonEmptyValue(
            in: values,
            keys: [
                "phase",
                "status",
                "activity",
                "state",
                "mode",
                "session.phase",
            ]
        ) {
            return humanize(explicit)
        }

        if let toolName = firstNonEmptyValue(
            in: values,
            keys: [
                "tool_name",
                "tool.name",
                "request.tool",
            ]
        ) {
            switch eventType {
            case .preToolUse:
                return toolName
            case .postToolUse:
                return "\(toolName) Done"
            case .permissionRequest:
                return "Waiting Approval"
            case .userPromptSubmit:
                return "Prompt Sent"
            case .sessionStart:
                return "Connected"
            case .stop:
                return "Stopped"
            case .unknown:
                break
            }
        }

        switch eventType {
        case .permissionRequest:
            return "Waiting Approval"
        case .preToolUse:
            return "Running"
        case .postToolUse:
            return "Done"
        case .sessionStart:
            return "Connected"
        case .stop:
            return "Stopped"
        case .userPromptSubmit:
            return "Prompt Sent"
        case .unknown:
            return "Active"
        }
    }

    private static func resolveCount(in values: [String: String], keys: [String]) -> Int? {
        for key in keys {
            if let raw = values[key], let count = Int(raw) {
                return count
            }
        }
        return nil
    }

    private static func firstNonEmptyValue(in values: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    private static func humanize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
