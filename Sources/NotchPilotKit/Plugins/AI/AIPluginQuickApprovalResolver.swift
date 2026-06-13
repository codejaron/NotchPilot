import Foundation

enum AIPluginQuickApprovalIntent: Equatable {
    case approve
    case reject
}

enum AIPluginQuickApprovalAction: Equatable {
    case claude(ApprovalAction)
    case codex(optionID: String?, action: CodexSurfaceAction)
}

struct AIPluginQuickApprovalActions: Equatable {
    let approve: AIPluginQuickApprovalAction?
    let reject: AIPluginQuickApprovalAction?

    var shouldRender: Bool {
        approve != nil || reject != nil
    }

    static let none = AIPluginQuickApprovalActions(approve: nil, reject: nil)
}

enum AIPluginQuickApprovalResolver {
    static func actions(for approval: PendingApproval) -> AIPluginQuickApprovalActions {
        AIPluginQuickApprovalActions(
            approve: ordinaryClaudeAllowAction(in: approval.availableActions).map {
                .claude($0)
            },
            reject: ordinaryClaudeDenyAction(in: approval.availableActions).map {
                .claude($0)
            }
        )
    }

    static func actions(for surface: CodexActionableSurface) -> AIPluginQuickApprovalActions {
        AIPluginQuickApprovalActions(
            approve: surface.quickActions.approveOptionID.map {
                .codex(optionID: $0, action: .primary)
            },
            reject: codexRejectAction(for: surface)
        )
    }

    private static func ordinaryClaudeAllowAction(in actions: [ApprovalAction]) -> ApprovalAction? {
        actions.first { action in
            guard action.id == "claude-allow",
                  case let .claude(decision) = action.payload,
                  decision.behavior == .allow,
                  decision.permissionUpdates.isEmpty
            else {
                return false
            }

            return true
        }
    }

    private static func ordinaryClaudeDenyAction(in actions: [ApprovalAction]) -> ApprovalAction? {
        actions.first { action in
            guard action.id == "claude-deny",
                  case let .claude(decision) = action.payload,
                  decision.behavior == .deny,
                  decision.feedbackText == nil
            else {
                return false
            }

            return true
        }
    }

    private static func codexRejectAction(for surface: CodexActionableSurface) -> AIPluginQuickApprovalAction? {
        if let rejectOptionID = surface.quickActions.rejectOptionID {
            return .codex(optionID: rejectOptionID, action: .primary)
        }

        if surface.quickActions.rejectUsesCancel {
            return .codex(optionID: nil, action: .cancel)
        }

        return nil
    }
}
