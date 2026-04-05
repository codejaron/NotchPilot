import Foundation

public enum AIHost: String, Codable, Equatable, Sendable {
    case claude
    case codex
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

    public init(
        title: String,
        toolName: String,
        previewText: String,
        filePath: String? = nil,
        command: String? = nil,
        diffContent: String? = nil
    ) {
        self.title = title
        self.toolName = toolName
        self.previewText = previewText
        self.filePath = filePath
        self.command = command
        self.diffContent = diffContent
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
