import Foundation

struct ClaudeToolUseCorrelator {
    private var cachedToolUseIDs: [ClaudeToolUseCorrelationKey: [String]] = [:]

    mutating func observe(
        sessionID: String,
        toolName: String?,
        toolInput: JSONValue?,
        toolUseID: String?
    ) {
        guard let toolUseID,
              let key = ClaudeToolUseCorrelationKey(
                sessionID: sessionID,
                toolName: toolName,
                toolInput: toolInput
              )
        else {
            return
        }

        cachedToolUseIDs[key, default: []].append(toolUseID)
    }

    mutating func observe(envelope: AIBridgeEnvelope) {
        guard envelope.eventType == .preToolUse else {
            return
        }

        observe(
            sessionID: envelope.sessionID,
            toolName: envelope.toolName,
            toolInput: envelope.toolInput,
            toolUseID: envelope.toolUseID
        )
    }

    mutating func correlatedToolUseID(
        sessionID: String,
        toolName: String?,
        toolInput: JSONValue?
    ) -> String? {
        guard let key = ClaudeToolUseCorrelationKey(
            sessionID: sessionID,
            toolName: toolName,
            toolInput: toolInput
        ),
            var queue = cachedToolUseIDs[key],
            queue.isEmpty == false
        else {
            return nil
        }

        let toolUseID = queue.removeFirst()
        if queue.isEmpty {
            cachedToolUseIDs.removeValue(forKey: key)
        } else {
            cachedToolUseIDs[key] = queue
        }
        return toolUseID
    }

    mutating func clear(sessionID: String) {
        for key in cachedToolUseIDs.keys where key.sessionID == sessionID {
            cachedToolUseIDs.removeValue(forKey: key)
        }
    }

    mutating func removeAll() {
        cachedToolUseIDs.removeAll()
    }
}

private struct ClaudeToolUseCorrelationKey: Hashable {
    let sessionID: String
    let toolName: String
    let inputFingerprint: String

    init?(sessionID: String, toolName: String?, toolInput: JSONValue?) {
        guard let normalizedToolName = Self.normalized(toolName) else {
            return nil
        }
        self.sessionID = sessionID
        self.toolName = normalizedToolName
        self.inputFingerprint = Self.fingerprint(for: toolInput)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed
    }

    private static func fingerprint(for toolInput: JSONValue?) -> String {
        guard let toolInput else {
            return "{}"
        }

        switch toolInput {
        case .object, .array:
            guard JSONSerialization.isValidJSONObject(toolInput.jsonObject),
                  let data = try? JSONSerialization.data(withJSONObject: toolInput.jsonObject, options: [.sortedKeys]),
                  let string = String(data: data, encoding: .utf8)
            else {
                return String(reflecting: toolInput)
            }
            return string
        case let .string(value):
            return value
        case let .integer(value):
            return "\(value)"
        case let .double(value):
            return "\(value)"
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }
}

struct ClaudeObservedToolUse {
    let toolUseID: String?

    init?(envelope: AIBridgeEnvelope) {
        guard case let .generic(values) = envelope.payload else {
            return nil
        }

        self.toolUseID = envelope.toolUseID ?? Self.firstNonEmptyValue(in: values, keys: [
            "tool_use_id",
            "toolUseID",
            "toolUseId",
        ])
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
