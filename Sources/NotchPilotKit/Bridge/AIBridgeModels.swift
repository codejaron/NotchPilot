import Foundation

public enum AIHost: String, Codable, Equatable, Sendable {
    case claude
    case codex
}

public enum ApprovalKind: Equatable, Sendable {
    case toolRequest
    case commandExecution
    case fileChange
    case networkAccess
}

public enum ApprovalActionStyle: Equatable, Sendable {
    case primary
    case secondary
    case destructive
    case outline
}

public struct NetworkApprovalContext: Equatable, Sendable {
    public let host: String
    public let protocolName: String
    public let port: Int?

    public init(host: String, protocolName: String, port: Int? = nil) {
        self.host = host
        self.protocolName = protocolName
        self.port = port
    }
}

public struct BridgeFrame: Codable, Equatable, Sendable {
    public let host: AIHost
    public let requestID: String
    public let rawJSON: String

    public init(host: AIHost, requestID: String, rawJSON: String) {
        self.host = host
        self.requestID = requestID
        self.rawJSON = rawJSON
    }
}

public enum AIBridgeEventType: Equatable, Sendable {
    case permissionRequest
    case preToolUse
    case postToolUse
    case sessionStart
    case stop
    case userPromptSubmit
    case unknown(String)
}

public struct AIBridgeCapabilities: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let persistentRules = AIBridgeCapabilities(rawValue: 1 << 0)
    public static let none: AIBridgeCapabilities = []

    public var supportsPersistentRules: Bool {
        contains(.persistentRules)
    }
}

public struct ApprovalPayload: Equatable, Sendable {
    public let title: String
    public let toolName: String
    public let previewText: String
    public let filePath: String?
    public let command: String?
    public let diffContent: String?
    public let originalContent: String?

    public init(
        title: String,
        toolName: String,
        previewText: String,
        filePath: String? = nil,
        command: String? = nil,
        diffContent: String? = nil,
        originalContent: String? = nil
    ) {
        self.title = title
        self.toolName = toolName
        self.previewText = previewText
        self.filePath = filePath
        self.command = command
        self.diffContent = diffContent
        self.originalContent = originalContent
    }
}

public enum AIBridgePayload: Equatable, Sendable {
    case permissionRequest(ApprovalPayload)
    case generic([String: String])
}

public struct AIBridgeEnvelope: Equatable, Sendable {
    public let host: AIHost
    public let requestID: String
    public let sessionID: String
    public let eventType: AIBridgeEventType
    public let capabilities: AIBridgeCapabilities
    public let needsResponse: Bool
    public let payload: AIBridgePayload

    public init(
        host: AIHost,
        requestID: String,
        sessionID: String,
        eventType: AIBridgeEventType,
        capabilities: AIBridgeCapabilities,
        needsResponse: Bool,
        payload: AIBridgePayload
    ) {
        self.host = host
        self.requestID = requestID
        self.sessionID = sessionID
        self.eventType = eventType
        self.capabilities = capabilities
        self.needsResponse = needsResponse
        self.payload = payload
    }
}

public enum ApprovalDecision: Equatable, Sendable {
    case allowOnce
    case denyOnce
    case persistAllowRule
}

public enum ApprovalActionPayload: Equatable, Sendable {
    case claude(ApprovalDecision)
}

public struct ApprovalAction: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let style: ApprovalActionStyle
    public let payload: ApprovalActionPayload

    public init(id: String, title: String, style: ApprovalActionStyle, payload: ApprovalActionPayload) {
        self.id = id
        self.title = title
        self.style = style
        self.payload = payload
    }

    public var legacyClaudeDecision: ApprovalDecision? {
        guard case let .claude(decision) = payload else {
            return nil
        }
        return decision
    }

    public static func claudeActions(
        eventType: AIBridgeEventType,
        supportsPersistentRules: Bool
    ) -> [ApprovalAction] {
        switch eventType {
        case .permissionRequest:
            var actions: [ApprovalAction] = [
                ApprovalAction(
                    id: "claude-deny",
                    title: "Deny",
                    style: .destructive,
                    payload: .claude(.denyOnce)
                ),
                ApprovalAction(
                    id: "claude-allow",
                    title: "Allow",
                    style: .primary,
                    payload: .claude(.allowOnce)
                ),
            ]
            if supportsPersistentRules {
                actions.append(
                    ApprovalAction(
                        id: "claude-always-allow",
                        title: "Always Allow",
                        style: .outline,
                        payload: .claude(.persistAllowRule)
                    )
                )
            }
            return actions
        case .preToolUse:
            var actions: [ApprovalAction] = [
                ApprovalAction(
                    id: "claude-deny",
                    title: "Deny",
                    style: .destructive,
                    payload: .claude(.denyOnce)
                ),
                ApprovalAction(
                    id: "claude-allow",
                    title: "Allow",
                    style: .primary,
                    payload: .claude(.allowOnce)
                ),
            ]
            if supportsPersistentRules {
                actions.append(
                    ApprovalAction(
                        id: "claude-always-allow",
                        title: "Always Allow",
                        style: .outline,
                        payload: .claude(.persistAllowRule)
                    )
                )
            }
            return actions
        default:
            return []
        }
    }
}
