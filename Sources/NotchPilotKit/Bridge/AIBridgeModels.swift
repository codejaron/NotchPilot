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

public struct ClaudeQuestionOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

public struct ClaudeUserQuestion: Equatable, Sendable, Identifiable {
    public let id: String
    public let header: String?
    public let question: String
    public let options: [ClaudeQuestionOption]
    public let multiSelect: Bool

    public init(
        id: String,
        header: String? = nil,
        question: String,
        options: [ClaudeQuestionOption],
        multiSelect: Bool = false
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
    }
}

public struct ApprovalPayload: Equatable, Sendable {
    public let title: String
    public let toolName: String
    public let description: String?
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
    public let permissionSuggestions: [JSONValue]
    public let toolInput: JSONValue?
    public let claudeQuestions: [ClaudeUserQuestion]

    public init(
        title: String,
        toolName: String,
        description: String? = nil,
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
        permissionMode: String? = nil,
        permissionSuggestions: [JSONValue] = [],
        toolInput: JSONValue? = nil,
        claudeQuestions: [ClaudeUserQuestion] = []
    ) {
        self.title = title
        self.toolName = toolName
        self.description = description
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
        self.permissionSuggestions = permissionSuggestions
        self.toolInput = toolInput
        self.claudeQuestions = claudeQuestions
    }

    public func updatedInput(answering answers: [String: String]) -> JSONValue {
        var object = toolInput?.objectValue ?? [:]
        object["answers"] = .object(answers.mapValues { .string($0) })
        return .object(object)
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
    public var permissionUpdates: [JSONValue]
    public var updatedInput: JSONValue?

    public init(
        behavior: Behavior,
        feedbackText: String? = nil,
        persistRule: ClaudePermissionRule? = nil,
        sessionRule: ClaudePermissionRule? = nil,
        permissionUpdates: [JSONValue] = [],
        updatedInput: JSONValue? = nil
    ) {
        self.behavior = behavior
        self.feedbackText = feedbackText
        self.persistRule = persistRule
        self.sessionRule = sessionRule
        self.permissionUpdates = permissionUpdates
        self.updatedInput = updatedInput
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
        mcpTool: String?,
        permissionSuggestions: [JSONValue] = []
    ) -> [ApprovalAction] {
        if toolName == "AskUserQuestion" {
            return []
        }

        let permissionSuggestion = bestAllowPermissionSuggestion(in: permissionSuggestions)
        var actions = [
            ApprovalAction(
                id: "claude-deny",
                title: "Deny",
                style: .outline,
                payload: .claude(.denyOnce)
            ),
            ApprovalAction(
                id: "claude-allow",
                title: "Allow once",
                style: permissionSuggestion == nil ? .primary : .outline,
                payload: .claude(.allowOnce)
            )
        ]

        if let permissionSuggestion {
            actions.append(
                ApprovalAction(
                    id: "claude-allow-persist",
                    title: title(forPermissionSuggestion: permissionSuggestion),
                    style: .primary,
                    payload: .claude(
                        ApprovalDecision(
                            behavior: .allow,
                            permissionUpdates: [permissionSuggestion]
                        )
                    )
                )
            )
        }

        return actions
    }

    private static func bestAllowPermissionSuggestion(in suggestions: [JSONValue]) -> JSONValue? {
        suggestions.first { suggestion in
            guard let object = suggestion.objectValue else {
                return false
            }

            let type = object["type"]?.stringValue ?? ""
            if type == "setMode" {
                return true
            }

            return type == "addRules" && object["behavior"]?.stringValue == "allow"
        }
    }

    private static func title(forPermissionSuggestion suggestion: JSONValue) -> String {
        guard let object = suggestion.objectValue else {
            return "Always allow"
        }

        if object["destination"]?.stringValue == "session" {
            return "Allow for session"
        }

        return "Always allow"
    }
}
