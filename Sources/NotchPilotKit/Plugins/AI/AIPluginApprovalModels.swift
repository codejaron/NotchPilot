import AppKit
import SwiftUI

enum CommandDisplayText {
    static func userVisibleCommand(_ rawCommand: String) -> String {
        rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AIPluginApprovalSneakNotice: Equatable {
    let count: Int
    let text: String

    init?(pendingApprovals: [PendingApproval], codexSurface: CodexActionableSurface?) {
        if let codexSurface {
            self.count = max(1, pendingApprovals.count)
            self.text = Self.codexText(for: codexSurface)
            return
        }

        guard let approval = pendingApprovals.first else {
            return nil
        }

        self.count = pendingApprovals.count
        self.text = Self.approvalText(for: approval)
    }

    private static func codexText(for surface: CodexActionableSurface) -> String {
        let summary = surface.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return summary
        }

        if let commandPreview = surface.commandPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           commandPreview.isEmpty == false {
            return CommandDisplayText.userVisibleCommand(commandPreview)
        }

        return surface.summary
    }

    private static func approvalText(for approval: PendingApproval) -> String {
        let payload = approval.payload

        if let toolInputSummary = toolInputSummary(for: payload) {
            return "\(payload.toolName): \(toolInputSummary)"
        }

        if let networkApprovalContext = approval.networkApprovalContext {
            let portSuffix = networkApprovalContext.port.map { ":\($0)" } ?? ""
            return "\(payload.toolName): \(networkApprovalContext.protocolName.uppercased()) \(networkApprovalContext.host)\(portSuffix)"
        }

        if payload.previewText.isEmpty == false {
            return "\(payload.toolName): \(payload.previewText)"
        }

        if let filePath = payload.filePath, filePath.isEmpty == false {
            return "\(payload.toolName): \(filePath)"
        }

        return payload.toolName
    }

    private static func toolInputSummary(for payload: ApprovalPayload) -> String? {
        switch payload.toolKind {
        case .bash:
            return firstNonEmptyValue([
                payload.command,
                payload.toolInput?.objectValue?["command"]?.stringValue,
            ]).map(CommandDisplayText.userVisibleCommand)
        case .webFetch:
            return firstNonEmptyValue([
                payload.toolInput?.objectValue?["prompt"]?.stringValue,
            ])
        case .webSearch:
            return firstNonEmptyValue([
                payload.toolInput?.objectValue?["query"]?.stringValue,
            ])
        case .edit, .readOnly:
            return firstNonEmptyValue([
                payload.filePath,
                payload.toolInput?.objectValue?["file_path"]?.stringValue,
                payload.toolInput?.objectValue?["path"]?.stringValue,
            ])
        case .mcp, .other:
            return firstNonEmptyValue([
                payload.description,
                payload.command,
                payload.filePath,
                payload.toolInput?.objectValue?["prompt"]?.stringValue,
                payload.toolInput?.objectValue?["description"]?.stringValue,
                payload.previewText,
            ])
        }
    }

    private static func firstNonEmptyValue(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }
}

struct CodexApprovalDetailPresentation: Equatable {
    let summaryText: String?
    let commandText: String

    init(surface: CodexActionableSurface) {
        let trimmedSummary = surface.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = surface.commandPreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedCommand.isEmpty == false {
            self.summaryText = trimmedSummary.isEmpty ? nil : trimmedSummary
            self.commandText = CommandDisplayText.userVisibleCommand(trimmedCommand)
        } else {
            self.summaryText = nil
            self.commandText = trimmedSummary
        }
    }
}

struct ClaudeApprovalOptionPresentation: Equatable, Identifiable {
    let index: Int
    let title: String
    let action: ApprovalAction

    var id: String { action.id }
    var indexText: String { "\(index)." }

    static func options(
        for actions: [ApprovalAction],
        language: AppLanguage
    ) -> [ClaudeApprovalOptionPresentation] {
        officialOrderedActions(actions).enumerated().map { offset, action in
            ClaudeApprovalOptionPresentation(
                index: offset + 1,
                title: AppStrings.approvalActionTitle(action.title, id: action.id, language: language),
                action: action
            )
        }
    }

    private static func officialOrderedActions(_ actions: [ApprovalAction]) -> [ApprovalAction] {
        actions.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = officialRank(for: lhs.element)
                let rhsRank = officialRank(for: rhs.element)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func officialRank(for action: ApprovalAction) -> Int {
        switch action.id {
        case "claude-allow":
            return 0
        case "claude-allow-persist":
            return 1
        case "claude-deny":
            return 2
        default:
            switch action.payload {
            case let .claude(decision):
                return decision.behavior == .allow ? 1 : 2
            case .claudeDenyWithFeedback:
                return 3
            }
        }
    }
}

struct ClaudeApprovalInteractionState: Equatable {
    private(set) var focusedActionID: String?

    init(options: [ClaudeApprovalOptionPresentation]) {
        focusedActionID = options.first?.id
    }

    mutating func sync(options: [ClaudeApprovalOptionPresentation]) {
        if let focusedActionID,
           options.contains(where: { $0.id == focusedActionID }) {
            return
        }

        focusedActionID = options.first?.id
    }

    mutating func focus(
        actionID: String?,
        options: [ClaudeApprovalOptionPresentation]
    ) -> String? {
        guard let actionID,
              options.contains(where: { $0.id == actionID }) else {
            focusedActionID = options.first?.id
            return focusedActionID
        }

        focusedActionID = actionID
        return focusedActionID
    }

    mutating func moveUp(options: [ClaudeApprovalOptionPresentation]) -> String? {
        move(delta: -1, options: options)
    }

    mutating func moveDown(options: [ClaudeApprovalOptionPresentation]) -> String? {
        move(delta: 1, options: options)
    }

    func focusedAction(in options: [ClaudeApprovalOptionPresentation]) -> ApprovalAction? {
        guard let focusedActionID else {
            return options.first?.action
        }

        return options.first(where: { $0.id == focusedActionID })?.action ?? options.first?.action
    }

    private mutating func move(
        delta: Int,
        options: [ClaudeApprovalOptionPresentation]
    ) -> String? {
        guard options.isEmpty == false else {
            focusedActionID = nil
            return nil
        }

        let currentID = focusedActionID ?? options[0].id
        let currentIndex = options.firstIndex(where: { $0.id == currentID }) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), options.count - 1)
        focusedActionID = options[nextIndex].id
        return focusedActionID
    }
}

enum CodexApprovalTextInputIndexPlacement: Equatable {
    case outsideField
    case insideFieldLeading
}

struct CodexApprovalTextInputPresentation: Equatable {
    let indexText: String
    let indexPlacement: CodexApprovalTextInputIndexPlacement
    let placeholder: String

    static func standalone(
        textInput: CodexSurfaceTextInput,
        index: Int,
        language: AppLanguage = .zhHans
    ) -> CodexApprovalTextInputPresentation {
        CodexApprovalTextInputPresentation(
            indexText: "\(index).",
            indexPlacement: .insideFieldLeading,
            placeholder: textInput.title?.isEmpty == false
                ? AppStrings.codexOptionTitle(textInput.title ?? "", language: language)
                : AppStrings.text(.codexTextInputFallback, language: language)
        )
    }

    static func feedback(
        textInput: CodexSurfaceTextInput,
        option: CodexSurfaceOption,
        language: AppLanguage = .zhHans
    ) -> CodexApprovalTextInputPresentation {
        let localizedOptionTitle = AppStrings.codexOptionTitle(option.title, language: language)
        return CodexApprovalTextInputPresentation(
            indexText: "\(option.index).",
            indexPlacement: .insideFieldLeading,
            placeholder: textInput.title?.isEmpty == false
                ? AppStrings.codexOptionTitle(textInput.title ?? localizedOptionTitle, language: language)
                : localizedOptionTitle
        )
    }
}
