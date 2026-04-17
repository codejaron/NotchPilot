import Foundation

public struct HookResponseEncoder {
    private let permissionRuleStore: PermissionRuleWriting?

    public init(permissionRuleStore: PermissionRuleWriting? = nil) {
        self.permissionRuleStore = permissionRuleStore
    }

    public func encode(decision: ApprovalDecision, for host: AIHost, eventType: AIBridgeEventType) throws -> Data {
        if host == .claude, let rule = decision.persistRule {
            try? permissionRuleStore?.appendAllowRule(rule)
        }

        let reason = defaultReason(behavior: decision.behavior, feedback: decision.feedbackText)

        let response: String
        switch (host, eventType) {
        case (.claude, .permissionRequest):
            response = permissionRequestResponse(behavior: decision.behavior, reason: reason)
        case (.claude, .preToolUse):
            response = preToolUseResponse(behavior: decision.behavior, reason: reason)
        default:
            response = "{}"
        }

        return Data(response.utf8)
    }

    private func permissionRequestResponse(behavior: ApprovalDecision.Behavior, reason: String) -> String {
        let behaviorString = behavior == .allow ? "allow" : "deny"
        let escapedReason = escape(reason)
        return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\#(behaviorString)"},"reason":"\#(escapedReason)"}}"#
    }

    private func preToolUseResponse(behavior: ApprovalDecision.Behavior, reason: String) -> String {
        let behaviorString = behavior == .allow ? "allow" : "deny"
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
