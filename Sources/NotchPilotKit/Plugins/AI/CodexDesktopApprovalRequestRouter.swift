import Foundation

enum CodexDesktopApprovalMethod: String {
    case commandExecution = "item/commandExecution/requestApproval"
    case fileChange = "item/fileChange/requestApproval"
    case permissions = "item/permissions/requestApproval"
    case toolRequestUserInput = "item/tool/requestUserInput"
    case mcpServerElicitation = "mcpServer/elicitation/request"
}

enum CodexDesktopApprovalDelivery: Equatable {
    case response
    case threadFollower(ownerClientID: String, conversationID: String, version: Int)
}

enum CodexDesktopApprovalRequestRouter {
    static func method(for request: CodexDesktopIPCRequestFrame) -> CodexDesktopApprovalMethod? {
        CodexDesktopApprovalMethod(rawValue: request.method)
    }

    static func canHandle(_ request: CodexDesktopIPCRequestFrame?) -> Bool {
        guard let request, let method = method(for: request) else {
            return false
        }

        switch method {
        case .mcpServerElicitation:
            return isMCPToolApprovalElicitation(params: request.params)
        case .commandExecution,
             .fileChange,
             .permissions,
             .toolRequestUserInput:
            return true
        }
    }

    static func liveDelivery(for request: CodexDesktopIPCRequestFrame) -> CodexDesktopApprovalDelivery? {
        guard let method = method(for: request) else {
            return nil
        }

        switch method {
        case .commandExecution,
             .fileChange,
             .permissions,
             .toolRequestUserInput,
             .mcpServerElicitation:
            guard let conversationID = request.params.stringValue(at: ["threadId"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                conversationID.isEmpty == false
            else {
                return nil
            }

            let ownerClientID = request.sourceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ownerClientID.isEmpty == false else {
                return nil
            }

            return .threadFollower(ownerClientID: ownerClientID, conversationID: conversationID, version: 1)
        }
    }

    static func isMCPToolApprovalElicitation(params: [String: JSONValue]) -> Bool {
        let kindPaths = [
            ["_meta", "codex_approval_kind"],
            ["_meta", "codexApprovalKind"],
            ["meta", "codex_approval_kind"],
            ["meta", "codexApprovalKind"],
        ]

        return kindPaths.contains { path in
            params.stringValue(at: path) == "mcp_tool_call"
        }
    }
}
