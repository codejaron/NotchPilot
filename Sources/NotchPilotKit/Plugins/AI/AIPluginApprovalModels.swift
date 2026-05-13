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
        if let description = approval.payload.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           description.isEmpty == false {
            return description
        }

        if let command = approval.payload.command?.trimmingCharacters(in: .whitespacesAndNewlines),
           command.isEmpty == false {
            return CommandDisplayText.userVisibleCommand(command)
        }

        if let networkApprovalContext = approval.networkApprovalContext {
            let portSuffix = networkApprovalContext.port.map { ":\($0)" } ?? ""
            return "\(networkApprovalContext.protocolName.uppercased()) \(networkApprovalContext.host)\(portSuffix)"
        }

        if approval.payload.previewText.isEmpty == false {
            return approval.payload.previewText
        }

        if let filePath = approval.payload.filePath, filePath.isEmpty == false {
            return filePath
        }

        return approval.payload.toolName
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
