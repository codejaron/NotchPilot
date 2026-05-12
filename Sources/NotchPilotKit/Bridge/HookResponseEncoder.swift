import Foundation

public struct HookResponseEncoder {
    private let permissionRuleStore: PermissionRuleWriting?

    public init(permissionRuleStore: PermissionRuleWriting? = nil) {
        self.permissionRuleStore = permissionRuleStore
    }

    public func encode(decision: ApprovalDecision, for host: AIHost, eventType: AIBridgeEventType) throws -> Data {
        // Persistent allow-rules are written to the Claude Code permissions file.
        // Devin Local imports the same `~/.claude/settings.json`, so a rule
        // appended for either host is honored by both — we treat them identically.
        if host.isClaudeFamily, decision.permissionUpdates.isEmpty, let rule = decision.persistRule {
            try? permissionRuleStore?.appendAllowRule(rule)
        }

        let reason = defaultReason(behavior: decision.behavior, feedback: decision.feedbackText)

        let response: String
        switch (host, eventType) {
        case (.claude, .permissionRequest), (.devin, .permissionRequest):
            response = try permissionRequestResponse(
                behavior: decision.behavior,
                reason: reason,
                permissionUpdates: decision.permissionUpdates,
                updatedInput: decision.updatedInput
            )
        case (.claude, .preToolUse), (.devin, .preToolUse):
            response = try preToolUseResponse(
                behavior: decision.behavior,
                reason: reason,
                updatedInput: decision.updatedInput
            )
        default:
            response = "{}"
        }

        return Data(response.utf8)
    }

    private func permissionRequestResponse(
        behavior: ApprovalDecision.Behavior,
        reason: String,
        permissionUpdates: [JSONValue],
        updatedInput: JSONValue?
    ) throws -> String {
        let behaviorString = behavior == .allow ? "allow" : "deny"
        var decision: [String: Any] = [
            "behavior": behaviorString,
        ]

        if behavior == .allow, let updatedInput {
            decision["updatedInput"] = updatedInput.jsonObject
        }

        if behavior == .allow, permissionUpdates.isEmpty == false {
            decision["updatedPermissions"] = permissionUpdates.map(\.jsonObject)
        }

        if behavior == .deny {
            decision["message"] = reason
        }

        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func preToolUseResponse(
        behavior: ApprovalDecision.Behavior,
        reason: String,
        updatedInput: JSONValue?
    ) throws -> String {
        let behaviorString = behavior == .allow ? "allow" : "deny"
        if let updatedInput {
            var output: [String: Any] = [
                "hookEventName": "PreToolUse",
                "permissionDecision": behaviorString,
                "permissionDecisionReason": reason,
            ]
            output["updatedInput"] = updatedInput.jsonObject

            let response: [String: Any] = [
                "hookSpecificOutput": output,
            ]
            let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        let escapedReason = escape(reason)
        return #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"\#(behaviorString)","permissionDecisionReason":"\#(escapedReason)"}}"#
    }

    private func defaultReason(behavior: ApprovalDecision.Behavior, feedback: String?) -> String {
        if let feedback = feedback?.trimmingCharacters(in: .whitespacesAndNewlines), feedback.isEmpty == false {
            return feedback
        }
        return behavior == .allow ? "Approved via NotchPilot" : "Denied via NotchPilot"
    }

    private func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"":
                escaped.append("\\\"")
            case "\\":
                escaped.append("\\\\")
            case "\n":
                escaped.append("\\n")
            case "\r":
                escaped.append("\\r")
            case "\t":
                escaped.append("\\t")
            case "\u{08}":
                escaped.append("\\b")
            case "\u{0C}":
                escaped.append("\\f")
            default:
                if scalar.value < 0x20 {
                    escaped.append(String(format: "\\u%04x", scalar.value))
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }
}

public protocol PermissionRuleWriting: Sendable {
    func appendAllowRule(_ rule: ClaudePermissionRule) throws
}
