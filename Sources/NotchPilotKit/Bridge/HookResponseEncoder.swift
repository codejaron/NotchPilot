import Foundation

public struct HookResponseEncoder {
    public init() {}

    public func encode(decision: ApprovalDecision, for host: AIHost) throws -> Data {
        let response: String

        switch (host, decision) {
        case (.claude, .allowOnce):
            response = #"{"decision":"allow"}"#
        case (.claude, .denyOnce):
            response = #"{"decision":"deny"}"#
        case (.claude, .persistAllowRule):
            response = #"{"decision":"allow","persist":true}"#
        case (.codex, .allowOnce):
            response = #"{"action":"allow"}"#
        case (.codex, .denyOnce):
            response = #"{"action":"deny"}"#
        case (.codex, .persistAllowRule):
            response = #"{"action":"allow","persist":true}"#
        }

        return Data(response.utf8)
    }
}
