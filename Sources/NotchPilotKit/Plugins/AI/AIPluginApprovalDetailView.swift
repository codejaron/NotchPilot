import AppKit
import SwiftUI

/// Renders the approval detail panel for a `PendingApproval`.
///
/// Host-agnostic: the view receives bindings for the feedback / question
/// state owned by the parent (so the parent retains @State across approval
/// transitions) plus callbacks for navigation and decision delivery, allowing
/// the merged AI tab in Phase 4 to reuse this view across plugins.
struct AIPluginApprovalDetailView: View {
    let approval: PendingApproval
    @Binding var feedbackRequestID: String?
    @Binding var feedbackText: String
    @Binding var feedbackContentHeight: CGFloat
    @Binding var questionSelections: [String: Set<String>]
    @Binding var questionTextAnswers: [String: String]
    let onBack: () -> Void
    let onRespond: (ApprovalAction) -> Void

    @ObservedObject private var settingsStore = SettingsStore.shared

    private let claudeFeedbackFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            minimalBackButton
            if approval.payload.claudeQuestions.isEmpty {
                approvalCard
            } else {
                AIPluginClaudeQuestionView(
                    approval: approval,
                    questionSelections: $questionSelections,
                    questionTextAnswers: $questionTextAnswers,
                    onRespond: onRespond
                )
            }
        }
    }

    private var minimalBackButton: some View {
        Button {
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .frame(
                    width: CodexApprovalCompactLayout.headerButtonSize,
                    height: CodexApprovalCompactLayout.headerButtonSize
                )
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            codexApprovalSummary(claudeApprovalSummary)
            AIPluginApprovalCommandView(text: approvalCommandText)
            approvalButtons
            if feedbackRequestID == approval.requestID {
                approvalFeedbackInput
            }
        }
    }

    private var approvalButtons: some View {
        let accent = NotchPilotTheme.brand(for: approval.host)

        return HStack(spacing: 8) {
            ForEach(approval.availableActions) { action in
                Button {
                    handleApprovalAction(action)
                } label: {
                    Text(AppStrings.approvalActionTitle(
                        action.title,
                        id: action.id,
                        language: settingsStore.interfaceLanguage
                    ))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AIPluginApprovalStyle.foregroundColor(for: action.style))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AIPluginApprovalStyle.backgroundFill(for: action.style, accent: accent))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    AIPluginApprovalStyle.borderColor(for: action.style, accent: accent),
                                    lineWidth: AIPluginApprovalStyle.borderLineWidth(for: action.style)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var approvalFeedbackInput: some View {
        let sizing = CodexApprovalTextInputSizing(
            lineHeight: claudeFeedbackFont.lineHeight,
            verticalPadding: 12
        )

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                CodexApprovalTextEditor(
                    text: $feedbackText,
                    isEditable: true,
                    isFocused: feedbackRequestID == approval.requestID,
                    font: claudeFeedbackFont,
                    onFocus: {
                        feedbackRequestID = approval.requestID
                    },
                    onSubmit: {
                        submitClaudeFeedback()
                    },
                    onMoveUpBoundary: {},
                    onMoveDownBoundary: {},
                    onContentHeightChange: { contentHeight in
                        feedbackContentHeight = contentHeight
                    }
                )
                .frame(height: sizing.height(forContentHeight: feedbackContentHeight))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NotchPilotTheme.claude.opacity(0.42), lineWidth: 1)
                )

                if feedbackText.isEmpty {
                    Text(AppStrings.text(.tellClaudeWhatToChange, language: settingsStore.interfaceLanguage))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    submitClaudeFeedback()
                } label: {
                    Text(AppStrings.text(.send, language: settingsStore.interfaceLanguage))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(NotchPilotTheme.danger.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func codexApprovalSummary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var claudeApprovalSummary: String {
        if approval.approvalKind == .networkAccess {
            return AppStrings.text(.networkAccessRequest, language: settingsStore.interfaceLanguage)
        }
        let title = approval.payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false {
            return AppStrings.claudeApprovalTitle(title, language: settingsStore.interfaceLanguage)
        }
        return AppStrings.text(.claudeWaitingApproval, language: settingsStore.interfaceLanguage)
    }

    private var approvalCommandText: String {
        if let command = approval.payload.command, command.isEmpty == false {
            return CommandDisplayText.userVisibleCommand(command)
        }

        if let networkApprovalContext = approval.networkApprovalContext {
            return networkApprovalSummary(networkApprovalContext)
        }

        if approval.payload.previewText.isEmpty == false {
            return approval.payload.previewText
        }

        if let filePath = approval.payload.filePath, filePath.isEmpty == false {
            return filePath
        }

        return approval.payload.toolName
    }

    private func networkApprovalSummary(_ context: NetworkApprovalContext) -> String {
        let portSuffix = context.port.map { ":\($0)" } ?? ""
        return "\(context.protocolName.uppercased()) \(context.host)\(portSuffix)"
    }

    private func handleApprovalAction(_ action: ApprovalAction) {
        switch action.payload {
        case .claudeDenyWithFeedback:
            feedbackRequestID = approval.requestID
            feedbackText = ""
            feedbackContentHeight = 0
        case .claude:
            resetClaudeFeedback()
            onRespond(action)
        }
    }

    private func submitClaudeFeedback() {
        let action = ApprovalAction(
            id: "claude-deny-feedback-submit",
            title: AppStrings.text(.noTellClaudeWhy, language: settingsStore.interfaceLanguage),
            style: .destructive,
            payload: .claude(
                ApprovalDecision(
                    behavior: .deny,
                    feedbackText: feedbackText
                )
            )
        )
        resetClaudeFeedback()
        onRespond(action)
    }

    private func resetClaudeFeedback() {
        feedbackRequestID = nil
        feedbackText = ""
        feedbackContentHeight = 0
    }

}
