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

    @ObservedObject private var generalSettings = SettingsStore.shared.general

    @State private var claudeApprovalInteractionState: ClaudeApprovalInteractionState?

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
        let options = currentApprovalOptions

        return VStack(alignment: .leading, spacing: 10) {
            codexApprovalSummary(claudeApprovalSummary)
            AIPluginApprovalCommandView(text: approvalCommandText)
            approvalOptions
            if feedbackRequestID == approval.requestID {
                approvalFeedbackInput
            }
        }
        .background(
            CodexApprovalKeyMonitor(
                isEnabled: feedbackRequestID != approval.requestID && options.isEmpty == false,
                focusedTarget: claudeApprovalFocusedTarget(options: options),
                onMoveUp: {
                    moveClaudeApprovalFocusUp()
                },
                onMoveDown: {
                    moveClaudeApprovalFocusDown()
                },
                onSubmit: {
                    submitFocusedClaudeApproval()
                }
            )
            .allowsHitTesting(false)
        )
        .onAppear {
            syncClaudeApprovalInteraction(options: options)
        }
        .onChange(of: approval.requestID) { _, _ in
            syncClaudeApprovalInteraction(options: currentApprovalOptions)
        }
        .onChange(of: currentApprovalOptionIDs) { _, _ in
            syncClaudeApprovalInteraction(options: currentApprovalOptions)
        }
    }

    private var approvalOptions: some View {
        let accent = NotchPilotTheme.brand(for: approval.host)
        let options = currentApprovalOptions
        let focusedActionID = claudeApprovalInteractionState?.focusedActionID ?? options.first?.id

        return VStack(alignment: .leading, spacing: CodexApprovalCompactLayout.optionStackSpacing) {
            ForEach(options) { option in
                Button {
                    focusClaudeApproval(actionID: option.id, options: options)
                    handleApprovalAction(option.action)
                } label: {
                    approvalOptionLabel(option, accent: accent, isFocused: option.id == focusedActionID)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentApprovalOptions: [ClaudeApprovalOptionPresentation] {
        ClaudeApprovalOptionPresentation.options(
            for: approval.availableActions,
            language: generalSettings.interfaceLanguage
        )
    }

    private var currentApprovalOptionIDs: [String] {
        currentApprovalOptions.map(\.id)
    }

    private func approvalOptionLabel(
        _ option: ClaudeApprovalOptionPresentation,
        accent: Color,
        isFocused: Bool
    ) -> some View {
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent.opacity(0.92))
                .frame(width: 8)
                .opacity(isFocused ? 1 : 0)

            Text(option.indexText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    isFocused
                        ? accent
                        : NotchPilotTheme.islandTextSecondary
                )
                .frame(width: 22, alignment: .trailing)

            Text(option.title)
                .font(.system(
                    size: 12,
                    weight: isFocused ? .semibold : .medium,
                    design: .rounded
                ))
                .foregroundStyle(
                    NotchPilotTheme.islandTextPrimary.opacity(
                        isFocused ? 0.98 : 0.86
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CodexApprovalCompactLayout.optionHorizontalPadding)
        .padding(.vertical, CodexApprovalCompactLayout.optionVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: CodexApprovalCompactLayout.optionCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isFocused
                            ? [
                                accent.opacity(0.16),
                                accent.opacity(0.06),
                            ]
                            : [
                                Color.white.opacity(0.03),
                                Color.white.opacity(0.015),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: CodexApprovalCompactLayout.optionCornerRadius, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? accent.opacity(0.46)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .accessibilityLabel("\(option.indexText) \(option.title)")
        .help(option.title)
    }

    private func claudeApprovalFocusedTarget(
        options: [ClaudeApprovalOptionPresentation]
    ) -> CodexApprovalFocusTarget? {
        let focusedActionID = claudeApprovalInteractionState?.focusedActionID ?? options.first?.id
        return focusedActionID.map { .option(id: $0) }
    }

    private func syncClaudeApprovalInteraction(options: [ClaudeApprovalOptionPresentation]) {
        if var state = claudeApprovalInteractionState {
            state.sync(options: options)
            claudeApprovalInteractionState = state
            return
        }

        claudeApprovalInteractionState = ClaudeApprovalInteractionState(options: options)
    }

    private func focusClaudeApproval(
        actionID: String?,
        options: [ClaudeApprovalOptionPresentation]
    ) {
        var state = claudeApprovalInteractionState ?? ClaudeApprovalInteractionState(options: options)
        _ = state.focus(actionID: actionID, options: options)
        claudeApprovalInteractionState = state
    }

    private func moveClaudeApprovalFocusUp() {
        let options = currentApprovalOptions
        var state = claudeApprovalInteractionState ?? ClaudeApprovalInteractionState(options: options)
        _ = state.moveUp(options: options)
        claudeApprovalInteractionState = state
    }

    private func moveClaudeApprovalFocusDown() {
        let options = currentApprovalOptions
        var state = claudeApprovalInteractionState ?? ClaudeApprovalInteractionState(options: options)
        _ = state.moveDown(options: options)
        claudeApprovalInteractionState = state
    }

    private func submitFocusedClaudeApproval() {
        let options = currentApprovalOptions
        var state = claudeApprovalInteractionState ?? ClaudeApprovalInteractionState(options: options)
        state.sync(options: options)
        claudeApprovalInteractionState = state

        guard let action = state.focusedAction(in: options) else {
            return
        }

        handleApprovalAction(action)
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
                    Text(AppStrings.text(.tellClaudeWhatToChange, language: generalSettings.interfaceLanguage))
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
                    Text(AppStrings.text(.send, language: generalSettings.interfaceLanguage))
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
            return AppStrings.text(.networkAccessRequest, language: generalSettings.interfaceLanguage)
        }
        let title = approval.payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false {
            return AppStrings.claudeApprovalTitle(title, language: generalSettings.interfaceLanguage)
        }
        return AppStrings.text(.claudeWaitingApproval, language: generalSettings.interfaceLanguage)
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
            title: AppStrings.text(.noTellClaudeWhy, language: generalSettings.interfaceLanguage),
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
