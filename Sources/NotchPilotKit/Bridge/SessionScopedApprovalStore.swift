import Foundation

public protocol SessionScopedRuleStoring: Sendable {
    func addRule(_ rule: ClaudePermissionRule, sessionID: String)
    func matches(sessionID: String, payload: ApprovalPayload) -> Bool
    func clearSession(_ sessionID: String)
}

public final class SessionScopedApprovalStore: SessionScopedRuleStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var rulesBySession: [String: Set<ClaudePermissionRule>] = [:]

    public init() {}

    public func addRule(_ rule: ClaudePermissionRule, sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        rulesBySession[sessionID, default: []].insert(rule)
    }

    public func matches(sessionID: String, payload: ApprovalPayload) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let rules = rulesBySession[sessionID] else {
            return false
        }
        return rules.contains(where: { ruleMatches($0, payload: payload) })
    }

    public func clearSession(_ sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        rulesBySession.removeValue(forKey: sessionID)
    }

    public func rules(for sessionID: String) -> Set<ClaudePermissionRule> {
        lock.lock()
        defer { lock.unlock() }
        return rulesBySession[sessionID] ?? []
    }

    private func ruleMatches(_ rule: ClaudePermissionRule, payload: ApprovalPayload) -> Bool {
        switch rule {
        case let .tool(name):
            if name == "Edit", payload.toolKind == .edit {
                return true
            }
            return payload.toolName == name
        case let .bashPrefix(prefix):
            return payload.bashCommandPrefix == prefix
        case let .webFetchDomain(domain):
            return payload.webFetchDomain == domain
        case let .mcp(server, tool):
            return payload.mcpServer == server && payload.mcpTool == tool
        }
    }
}
