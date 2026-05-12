import AppKit
import SwiftUI

enum CommandDisplayText {
    static func userVisibleCommand(_ rawCommand: String) -> String {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let executable = nextToken(in: trimmed, from: trimmed.startIndex),
              isShellExecutable(executable.value)
        else {
            return trimmed
        }

        var cursor = executable.endIndex
        while let option = nextToken(in: trimmed, from: cursor) {
            guard option.value.hasPrefix("-") else {
                return trimmed
            }

            cursor = option.endIndex
            if option.value.dropFirst().contains("c") {
                let command = trimmed[cursor...].trimmingCharacters(in: .whitespacesAndNewlines)
                return command.isEmpty ? trimmed : unquoted(command)
            }
        }

        return trimmed
    }

    private struct Token {
        let value: String
        let endIndex: String.Index
    }

    private static func nextToken(in string: String, from startIndex: String.Index) -> Token? {
        var index = startIndex
        while index < string.endIndex, string[index].isWhitespace {
            index = string.index(after: index)
        }

        guard index < string.endIndex else {
            return nil
        }

        var value = ""
        var quote: Character?
        while index < string.endIndex {
            let character = string[index]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    value.append(character)
                }
                index = string.index(after: index)
                continue
            }

            if character.isWhitespace {
                break
            }

            if character == "'" || character == "\"" {
                quote = character
            } else {
                value.append(character)
            }
            index = string.index(after: index)
        }

        return Token(value: value, endIndex: index)
    }

    private static func isShellExecutable(_ executable: String) -> Bool {
        guard let name = executable.split(separator: "/").last else {
            return false
        }

        return ["bash", "sh", "zsh"].contains(String(name))
    }

    private static func unquoted(_ command: String) -> String {
        guard let first = command.first,
              (first == "'" || first == "\""),
              command.last == first,
              command.count >= 2
        else {
            return command
        }

        let inner = String(command.dropFirst().dropLast())
        guard first == "\"" else {
            return inner
        }

        return unescapedDoubleQuotedCommand(inner)
    }

    private static func unescapedDoubleQuotedCommand(_ command: String) -> String {
        var result = ""
        var isEscaping = false

        for character in command {
            if isEscaping {
                if character == "\\" || character == "\"" || character == "$" || character == "`" {
                    result.append(character)
                } else {
                    result.append("\\")
                    result.append(character)
                }
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }

        if isEscaping {
            result.append("\\")
        }
        return result
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
