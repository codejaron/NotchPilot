import Foundation

public struct HookResponseEncoder {
    public init() {}

    public func encode(decision: ApprovalDecision, for host: AIHost, eventType: AIBridgeEventType) throws -> Data {
        let response: String

        switch (host, eventType, decision) {
        case (.claude, .permissionRequest, .allowOnce):
            response = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        case (.claude, .permissionRequest, .denyOnce):
            response = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#
        case (.claude, .permissionRequest, .persistAllowRule):
            response = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","applyPermissionRule":true}}}"#
        case (.claude, .preToolUse, .allowOnce):
            response = #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Approved via NotchPilot"}}"#
        case (.claude, .preToolUse, .denyOnce):
            response = #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied via NotchPilot"}}"#
        case (.claude, .preToolUse, .persistAllowRule):
            response = #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Always allowed via NotchPilot"}}"#
        default:
            response = "{}"
        }

        return Data(response.utf8)
    }
}
