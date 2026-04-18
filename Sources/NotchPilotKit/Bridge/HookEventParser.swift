import Foundation

public enum HookEventParserError: Error, Equatable {
    case invalidJSON
    case unsupportedRootObject
}

public struct HookEventParser {
    private let loadFileContent: @Sendable (String) -> String?

    public init(loadFileContent: @escaping @Sendable (String) -> String? = { path in
        try? String(contentsOfFile: path, encoding: .utf8)
    }) {
        self.loadFileContent = loadFileContent
    }

    public func parse(frame: BridgeFrame) throws -> AIBridgeEnvelope {
        guard let data = frame.rawJSON.data(using: .utf8) else {
            throw HookEventParserError.invalidJSON
        }

        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HookEventParserError.invalidJSON
        }

        guard let dictionary = rawObject as? [String: Any] else {
            throw HookEventParserError.unsupportedRootObject
        }

        let eventType = resolveEventType(from: dictionary)
        let sessionID = resolveSessionID(from: dictionary, fallback: frame.requestID)
        let capabilities = resolveCapabilities(from: dictionary)
        let toolName = findString(in: dictionary, paths: [
            ["tool_name"],
            ["tool", "name"],
            ["request", "tool"],
        ])
        let permissionMode = findString(in: dictionary, paths: [
            ["permission_mode"],
            ["permissionMode"],
        ])
        let needsResponse = Self.shouldRequestDecision(
            eventType: eventType,
            toolName: toolName,
            permissionMode: permissionMode
        )
        let payload = resolvePayload(from: dictionary, eventType: eventType, permissionMode: permissionMode)

        return AIBridgeEnvelope(
            host: frame.host,
            requestID: frame.requestID,
            sessionID: sessionID,
            eventType: eventType,
            capabilities: capabilities,
            needsResponse: needsResponse,
            launchContext: frame.origin,
            payload: payload
        )
    }

    static let readOnlyToolNames: Set<String> = [
        "Read",
        "Glob",
        "Grep",
        "WebSearch",
        "TodoWrite",
        "ExitPlanMode",
        "NotebookRead",
        "Task",
    ]

    static let editToolNames: Set<String> = [
        "Edit",
        "Write",
        "MultiEdit",
        "NotebookEdit",
    ]

    static func resolveToolKind(toolName: String) -> ClaudeToolKind {
        if toolName.hasPrefix("mcp__") {
            return .mcp
        }
        switch toolName {
        case "Bash":
            return .bash
        case "WebFetch":
            return .webFetch
        case "WebSearch":
            return .webSearch
        default:
            if editToolNames.contains(toolName) {
                return .edit
            }
            if readOnlyToolNames.contains(toolName) {
                return .readOnly
            }
            return .other
        }
    }

    static func extractBashCommandPrefix(from command: String?) -> String? {
        guard let command = command?.trimmingCharacters(in: .whitespaces), command.isEmpty == false else {
            return nil
        }
        let firstClause = command
            .split(whereSeparator: { $0 == "|" || $0 == ";" || $0 == "&" })
            .first
            .map(String.init) ?? command
        let tokens = firstClause
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { $0.contains("=") == false || $0.hasPrefix("-") }
        guard let head = tokens.first else {
            return nil
        }
        let base = (head as NSString).lastPathComponent
        let twoTokenCommands: Set<String> = ["git", "npm", "yarn", "pnpm", "bun", "cargo", "go", "kubectl", "docker", "brew", "gh", "pip"]
        if twoTokenCommands.contains(base), tokens.count >= 2 {
            let second = tokens[1]
            if second.hasPrefix("-") == false {
                return "\(base) \(second)"
            }
        }
        return base
    }

    static func extractDomain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString), let host = url.host else {
            return nil
        }
        return host
    }

    static func extractMCP(from toolName: String) -> (server: String?, tool: String?) {
        guard toolName.hasPrefix("mcp__") else {
            return (nil, nil)
        }
        let stripped = String(toolName.dropFirst("mcp__".count))
        let parts = stripped.components(separatedBy: "__")
        guard parts.count >= 2 else {
            return (nil, nil)
        }
        return (parts[0], parts.dropFirst().joined(separator: "__"))
    }

    static func shouldRequestDecision(
        eventType: AIBridgeEventType,
        toolName: String?,
        permissionMode: String?
    ) -> Bool {
        switch eventType {
        case .permissionRequest:
            return true
        case .preToolUse:
            break
        default:
            return false
        }

        if permissionMode == "bypassPermissions" {
            return false
        }

        if let toolName, readOnlyToolNames.contains(toolName) {
            return false
        }

        if permissionMode == "plan" {
            return false
        }

        if permissionMode == "acceptEdits", let toolName, editToolNames.contains(toolName) {
            return false
        }

        return true
    }

    private func resolveEventType(from dictionary: [String: Any]) -> AIBridgeEventType {
        let rawType = findString(in: dictionary, paths: [
            ["hook_event_name"],
            ["event"],
            ["eventType"],
            ["type"],
        ]) ?? "unknown"

        switch rawType.lowercased() {
        case "permissionrequest":
            return .permissionRequest
        case "pretooluse":
            return .preToolUse
        case "posttooluse":
            return .postToolUse
        case "sessionstart", "session_start":
            return .sessionStart
        case "stop", "sessionstop", "session_stop":
            return .stop
        case "userpromptsubmit":
            return .userPromptSubmit
        default:
            return .unknown(rawType)
        }
    }

    private func resolveSessionID(from dictionary: [String: Any], fallback: String) -> String {
        findString(in: dictionary, paths: [
            ["session_id"],
            ["sessionId"],
            ["session", "id"],
        ]) ?? fallback
    }

    private func resolveCapabilities(from dictionary: [String: Any]) -> AIBridgeCapabilities {
        let supportsPersistentRules = findBool(in: dictionary, paths: [
            ["capabilities", "supports_persistent_rules"],
            ["capabilities", "supportsPersistentRules"],
            ["supports_persistent_rules"],
            ["supportsPersistentRules"],
        ]) ?? false

        var capabilities: AIBridgeCapabilities = .none
        if supportsPersistentRules {
            capabilities.insert(.persistentRules)
        }
        return capabilities
    }

    private func resolvePayload(
        from dictionary: [String: Any],
        eventType: AIBridgeEventType,
        permissionMode: String?
    ) -> AIBridgePayload {
        switch eventType {
        case .permissionRequest, .preToolUse:
            let toolName = findString(in: dictionary, paths: [
                ["tool_name"],
                ["tool", "name"],
                ["request", "tool"],
            ]) ?? "Action"

            let command = findString(in: dictionary, paths: [
                ["tool_input", "command"],
                ["tool", "input", "command"],
                ["command"],
                ["request", "command"],
            ])

            let filePath = findString(in: dictionary, paths: [
                ["tool_input", "file_path"],
                ["tool", "input", "file_path"],
                ["file_path"],
            ])

            let diffContent = findString(in: dictionary, paths: [
                ["tool_input", "content"],
                ["tool_input", "new_string"],
                ["tool_input", "newString"],
                ["tool", "input", "content"],
                ["tool", "input", "new_string"],
                ["tool", "input", "newString"],
            ])

            let originalContent = findString(in: dictionary, paths: [
                ["tool_input", "old_string"],
                ["tool_input", "oldString"],
                ["tool_input", "old_content"],
                ["tool", "input", "old_string"],
                ["tool", "input", "oldString"],
                ["tool", "input", "old_content"],
            ]) ?? fallbackOriginalContent(filePath: filePath, newContent: diffContent)

            let webFetchURL = findString(in: dictionary, paths: [
                ["tool_input", "url"],
                ["tool", "input", "url"],
            ])

            let toolKind = Self.resolveToolKind(toolName: toolName)
            let bashPrefix = toolKind == .bash ? Self.extractBashCommandPrefix(from: command) : nil
            let domain = toolKind == .webFetch ? Self.extractDomain(from: webFetchURL) : nil
            let (mcpServer, mcpTool) = toolKind == .mcp ? Self.extractMCP(from: toolName) : (nil, nil)

            let previewText = command
                ?? filePath
                ?? webFetchURL
                ?? findString(in: dictionary, paths: [["prompt"]])
                ?? "Review the requested action."

            return .permissionRequest(
                ApprovalPayload(
                    title: "\(toolName) wants approval",
                    toolName: toolName,
                    previewText: previewText,
                    filePath: filePath,
                    command: command,
                    diffContent: diffContent,
                    originalContent: originalContent,
                    toolKind: toolKind,
                    bashCommandPrefix: bashPrefix,
                    webFetchURL: webFetchURL,
                    webFetchDomain: domain,
                    mcpServer: mcpServer,
                    mcpTool: mcpTool,
                    permissionMode: permissionMode
                )
            )
        case .userPromptSubmit:
            var values = flattenStrings(from: dictionary)
            if let prompt = findString(in: dictionary, paths: [
                ["prompt"],
                ["user_prompt"],
                ["message"],
            ]) {
                values["prompt"] = prompt
            }
            return .generic(values)
        default:
            return .generic(flattenStrings(from: dictionary))
        }
    }

    private func flattenStrings(from dictionary: [String: Any]) -> [String: String] {
        flatten(dictionary: dictionary)
    }

    private func flatten(dictionary: [String: Any], prefix: String = "") -> [String: String] {
        dictionary.reduce(into: [:]) { partialResult, item in
            let key = prefix.isEmpty ? item.key : "\(prefix).\(item.key)"

            switch item.value {
            case let string as String:
                partialResult[key] = string
            case let number as NSNumber:
                partialResult[key] = number.stringValue
            case let bool as Bool:
                partialResult[key] = bool ? "true" : "false"
            case let childDictionary as [String: Any]:
                partialResult.merge(flatten(dictionary: childDictionary, prefix: key)) { current, _ in current }
            default:
                break
            }
        }
    }

    private func findString(in dictionary: [String: Any], paths: [[String]]) -> String? {
        for path in paths {
            if let value = value(in: dictionary, for: path) as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func findBool(in dictionary: [String: Any], paths: [[String]]) -> Bool? {
        for path in paths {
            if let value = value(in: dictionary, for: path) as? Bool {
                return value
            }
        }
        return nil
    }

    private func value(in dictionary: [String: Any], for path: [String]) -> Any? {
        var current: Any = dictionary

        for component in path {
            guard let dict = current as? [String: Any], let next = dict[component] else {
                return nil
            }
            current = next
        }

        return current
    }
    private func fallbackOriginalContent(filePath: String?, newContent: String?) -> String? {
        guard let filePath, let newContent, newContent.isEmpty == false else {
            return nil
        }

        return loadFileContent(filePath)
    }
}
