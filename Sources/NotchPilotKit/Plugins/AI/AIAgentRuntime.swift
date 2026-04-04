import Foundation

public struct AISession: Equatable, Sendable, Identifiable {
    public let id: String
    public let host: AIHost
    public var lastEventType: AIBridgeEventType
    public var activityLabel: String
    public var inputTokenCount: Int?
    public var outputTokenCount: Int?
    public var updatedAt: Date

    public init(
        id: String,
        host: AIHost,
        lastEventType: AIBridgeEventType,
        activityLabel: String,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.host = host
        self.lastEventType = lastEventType
        self.activityLabel = activityLabel
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.updatedAt = updatedAt
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
    public let payload: ApprovalPayload
    public let capabilities: AIBridgeCapabilities
    public var status: ApprovalStatus
    public let createdAt: Date

    public init(
        requestID: String,
        sessionID: String,
        host: AIHost,
        payload: ApprovalPayload,
        capabilities: AIBridgeCapabilities,
        status: ApprovalStatus,
        createdAt: Date = Date()
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.host = host
        self.payload = payload
        self.capabilities = capabilities
        self.status = status
        self.createdAt = createdAt
    }
}

public final class AIAgentRuntime {
    public enum HandleResult: Equatable {
        case respondNow(Data)
        case awaitDecision(requestID: String)
    }

    public private(set) var sessions: [AISession] = []
    public private(set) var pendingApprovals: [PendingApproval] = []

    public init() {}

    @discardableResult
    public func handle(envelope: AIBridgeEnvelope) -> HandleResult {
        refreshSession(id: envelope.sessionID, host: envelope.host, eventType: envelope.eventType, payload: envelope.payload)

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
            payload: payload,
            capabilities: envelope.capabilities,
            status: .pending
        )

        pendingApprovals.removeAll(where: { $0.requestID == envelope.requestID })
        pendingApprovals.append(approval)
        pendingApprovals.sort { $0.createdAt < $1.createdAt }

        return .awaitDecision(requestID: envelope.requestID)
    }

    @discardableResult
    public func resolvePendingApproval(requestID: String) -> PendingApproval? {
        mutatePendingApproval(requestID: requestID, newStatus: .resolved)
    }

    @discardableResult
    public func expirePendingApproval(requestID: String) -> PendingApproval? {
        mutatePendingApproval(requestID: requestID, newStatus: .expired)
    }

    private func refreshSession(id: String, host: AIHost, eventType: AIBridgeEventType, payload: AIBridgePayload) {
        let activity = SessionActivity(eventType: eventType, payload: payload)

        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].lastEventType = eventType
            sessions[index].activityLabel = activity.label
            sessions[index].inputTokenCount = activity.inputTokenCount
            sessions[index].outputTokenCount = activity.outputTokenCount
            sessions[index].updatedAt = Date()
            sessions.sort { $0.updatedAt > $1.updatedAt }
            return
        }

        sessions.append(
            AISession(
                id: id,
                host: host,
                lastEventType: eventType,
                activityLabel: activity.label,
                inputTokenCount: activity.inputTokenCount,
                outputTokenCount: activity.outputTokenCount
            )
        )
        sessions.sort { $0.updatedAt > $1.updatedAt }
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
            default:
                break
            }
        }

        switch eventType {
        case .permissionRequest:
            return "Waiting Approval"
        case .preToolUse:
            return "Running"
        case .postToolUse:
            return "Complete"
        case .sessionStart:
            return "Connected"
        case .stop:
            return "Stopped"
        case let .unknown(value):
            return humanize(value)
        }
    }

    private static func firstNonEmptyValue(in values: [String: String], keys: [String]) -> String? {
        keys.first { key in
            guard let value = values[key] else { return false }
            return value.isEmpty == false
        }
        .flatMap { values[$0] }
    }

    private static func resolveCount(in values: [String: String], keys: [String]) -> Int? {
        for key in keys {
            guard let rawValue = values[key] else { continue }
            let digits = rawValue.filter(\.isNumber)
            if let value = Int(digits.isEmpty ? rawValue : digits) {
                return value
            }
        }
        return nil
    }

    private static func humanize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
