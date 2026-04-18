import Foundation

public enum AIHost: String, Codable, Equatable, Sendable {
    case claude
    case codex
}

public struct AISessionLaunchContext: Codable, Equatable, Sendable {
    public let processIdentifier: Int32?
    public let bundleIdentifier: String?
    public let terminalIdentifier: String?
    public let codexClientID: String?

    public init(
        processIdentifier: Int32? = nil,
        bundleIdentifier: String? = nil,
        terminalIdentifier: String? = nil,
        codexClientID: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = Self.normalized(bundleIdentifier)
        self.terminalIdentifier = Self.normalized(terminalIdentifier)
        self.codexClientID = Self.normalized(codexClientID)
    }

    public var isEmpty: Bool {
        processIdentifier == nil
            && bundleIdentifier == nil
            && terminalIdentifier == nil
            && codexClientID == nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed
    }
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
    public let origin: AISessionLaunchContext?
    public let rawJSON: String

    public init(
        host: AIHost,
        requestID: String,
        origin: AISessionLaunchContext? = nil,
        rawJSON: String
    ) {
        self.host = host
        self.requestID = requestID
        self.origin = origin?.isEmpty == true ? nil : origin
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

public enum ClaudeToolKind: Equatable, Sendable {
    case edit
    case bash
    case webFetch
    case webSearch
    case mcp
    case readOnly
    case other
}

public struct ApprovalPayload: Equatable, Sendable {
    public let title: String
    public let toolName: String
    public let previewText: String
    public let filePath: String?
    public let command: String?
    public let diffContent: String?
    public let originalContent: String?
    public let toolKind: ClaudeToolKind
    public let bashCommandPrefix: String?
    public let webFetchURL: String?
    public let webFetchDomain: String?
    public let mcpServer: String?
    public let mcpTool: String?
    public let permissionMode: String?

    public init(
        title: String,
        toolName: String,
        previewText: String,
        filePath: String? = nil,
        command: String? = nil,
        diffContent: String? = nil,
        originalContent: String? = nil,
        toolKind: ClaudeToolKind = .other,
        bashCommandPrefix: String? = nil,
        webFetchURL: String? = nil,
        webFetchDomain: String? = nil,
        mcpServer: String? = nil,
        mcpTool: String? = nil,
        permissionMode: String? = nil
    ) {
        self.title = title
        self.toolName = toolName
        self.previewText = previewText
        self.filePath = filePath
        self.command = command
        self.diffContent = diffContent
        self.originalContent = originalContent
        self.toolKind = toolKind
        self.bashCommandPrefix = bashCommandPrefix
        self.webFetchURL = webFetchURL
        self.webFetchDomain = webFetchDomain
        self.mcpServer = mcpServer
        self.mcpTool = mcpTool
        self.permissionMode = permissionMode
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
    public let launchContext: AISessionLaunchContext?
    public let payload: AIBridgePayload

    public init(
        host: AIHost,
        requestID: String,
        sessionID: String,
        eventType: AIBridgeEventType,
        capabilities: AIBridgeCapabilities,
        needsResponse: Bool,
        launchContext: AISessionLaunchContext? = nil,
        payload: AIBridgePayload
    ) {
        self.host = host
        self.requestID = requestID
        self.sessionID = sessionID
        self.eventType = eventType
        self.capabilities = capabilities
        self.needsResponse = needsResponse
        self.launchContext = launchContext?.isEmpty == true ? nil : launchContext
        self.payload = payload
    }
}

public enum ClaudePermissionRule: Equatable, Sendable, Hashable {
    case tool(String)
    case bashPrefix(String)
    case webFetchDomain(String)
    case mcp(server: String, tool: String)

    public var ruleString: String {
        switch self {
        case let .tool(name):
            return name
        case let .bashPrefix(prefix):
            return "Bash(\(prefix):*)"
        case let .webFetchDomain(domain):
            return "WebFetch(domain:\(domain))"
        case let .mcp(server, tool):
            return "mcp__\(server)__\(tool)"
        }
    }
}

public struct ApprovalDecision: Equatable, Sendable {
    public enum Behavior: Equatable, Sendable {
        case allow
        case deny
    }

    public var behavior: Behavior
    public var feedbackText: String?
    public var persistRule: ClaudePermissionRule?
    public var sessionRule: ClaudePermissionRule?

    public init(
        behavior: Behavior,
        feedbackText: String? = nil,
        persistRule: ClaudePermissionRule? = nil,
        sessionRule: ClaudePermissionRule? = nil
    ) {
        self.behavior = behavior
        self.feedbackText = feedbackText
        self.persistRule = persistRule
        self.sessionRule = sessionRule
    }

    public static let allowOnce = ApprovalDecision(behavior: .allow)
    public static let denyOnce = ApprovalDecision(behavior: .deny)
}

public enum ApprovalActionPayload: Equatable, Sendable {
    case claude(ApprovalDecision)
    case claudeDenyWithFeedback
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

    public static func claudeActions(
        toolKind: ClaudeToolKind,
        toolName: String,
        bashCommandPrefix: String?,
        webFetchDomain: String?,
        mcpServer: String?,
        mcpTool: String?
    ) -> [ApprovalAction] {
        let (secondaryTitle, secondaryDecision): (String, ApprovalDecision) = {
            switch toolKind {
            case .edit:
                return (
                    "Yes, allow edits for this session",
                    ApprovalDecision(
                        behavior: .allow,
                        sessionRule: .tool("Edit")
                    )
                )
            case .bash:
                if let prefix = bashCommandPrefix, prefix.isEmpty == false {
                    return (
                        "Yes, don't ask for `\(prefix)` again",
                        ApprovalDecision(
                            behavior: .allow,
                            persistRule: .bashPrefix(prefix)
                        )
                    )
                }
                return (
                    "Yes, always allow \(toolName)",
                    ApprovalDecision(
                        behavior: .allow,
                        persistRule: .tool(toolName)
                    )
                )
            case .webFetch:
                if let domain = webFetchDomain, domain.isEmpty == false {
                    return (
                        "Yes, don't ask for `\(domain)` again",
                        ApprovalDecision(
                            behavior: .allow,
                            persistRule: .webFetchDomain(domain)
                        )
                    )
                }
                return (
                    "Yes, always allow WebFetch",
                    ApprovalDecision(
                        behavior: .allow,
                        persistRule: .tool("WebFetch")
                    )
                )
            case .mcp:
                if let server = mcpServer, let tool = mcpTool,
                   server.isEmpty == false, tool.isEmpty == false {
                    return (
                        "Yes, always allow `\(tool)`",
                        ApprovalDecision(
                            behavior: .allow,
                            persistRule: .mcp(server: server, tool: tool)
                        )
                    )
                }
                return (
                    "Yes, always allow \(toolName)",
                    ApprovalDecision(
                        behavior: .allow,
                        persistRule: .tool(toolName)
                    )
                )
            case .webSearch, .readOnly, .other:
                return (
                    "Yes, always allow \(toolName)",
                    ApprovalDecision(
                        behavior: .allow,
                        persistRule: .tool(toolName)
                    )
                )
            }
        }()

        return [
            ApprovalAction(
                id: "claude-allow",
                title: "Yes",
                style: .primary,
                payload: .claude(.allowOnce)
            ),
            ApprovalAction(
                id: "claude-allow-persist",
                title: secondaryTitle,
                style: .outline,
                payload: .claude(secondaryDecision)
            ),
            ApprovalAction(
                id: "claude-deny-feedback",
                title: "No, and tell Claude what to do differently",
                style: .destructive,
                payload: .claudeDenyWithFeedback
            ),
        ]
    }
}
