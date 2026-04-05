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
        let needsResponse = eventType == .permissionRequest || eventType == .preToolUse
        let payload = resolvePayload(from: dictionary, eventType: eventType)

        return AIBridgeEnvelope(
            host: frame.host,
            requestID: frame.requestID,
            sessionID: sessionID,
            eventType: eventType,
            capabilities: capabilities,
            needsResponse: needsResponse,
            payload: payload
        )
    }

    private func resolveEventType(from dictionary: [String: Any]) -> AIBridgeEventType {
        let rawType = findString(in: dictionary, paths: [
            ["hook_event_name"],
            ["event"],
            ["eventType"],
            ["type"],
        ]) ?? "unknown"

        switch rawType.lowercased() {
        case "permissionrequest", "approval_request":
            return .permissionRequest
        case "pretooluse":
            return .preToolUse
        case "posttooluse":
            return .postToolUse
        case "sessionstart", "session_start":
            return .sessionStart
        case "stop", "sessionstop", "session_stop":
            return .stop
        case "userpromptsubmit", "user_prompt_submit":
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

    private func resolvePayload(from dictionary: [String: Any], eventType: AIBridgeEventType) -> AIBridgePayload {
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

            let previewText = command
                ?? filePath
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
                    originalContent: originalContent
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
