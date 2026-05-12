import AppKit
import SwiftUI

/// Renders the Codex surface detail view (command preview + options + action buttons + key monitor).
///
/// Plugin-agnostic: takes the surface plus bindings for transient interaction state and
/// closures for plugin actions. Phase 4's merged AI view will host this for any session
/// whose host is `.codex`.
struct AIPluginCodexSurfaceView: View {
    let surface: CodexActionableSurface
    @Binding var interactionState: CodexApprovalInteractionState?
    @Binding var textDraftSurfaceID: String?
    @Binding var textDraft: String
    @Binding var textInputContentHeight: CGFloat
    let onBack: () -> Void
    let onAction: (CodexSurfaceAction) -> Void
    let onSelectOption: (String) -> Void
    let onUpdateText: (String) -> Void

    @ObservedObject private var settingsStore = SettingsStore.shared

    private let codexTextInputFont = NSFont.systemFont(
        ofSize: CodexApprovalCompactLayout.textInputFontSize,
        weight: .medium
    )

    var body: some View {
        codexSurfaceDetailView(surface)
    }

    private func codexSurfaceDetailView(_ surface: CodexActionableSurface) -> some View {
        let presentation = CodexApprovalDetailPresentation(surface: surface)

        return VStack(alignment: .leading, spacing: CodexApprovalCompactLayout.detailSpacing) {
            codexSurfaceDetailHeader(surface, presentation: presentation)
            codexSurfaceCard(surface, presentation: presentation)
        }
        .background(
            CodexApprovalKeyMonitor(
                isEnabled: true,
                focusedTarget: interactionState?.focusedTarget,
                onMoveUp: {
                    moveCodexApprovalFocusUp(surface: surface)
                },
                onMoveDown: {
                    moveCodexApprovalFocusDown(surface: surface)
                },
                onSubmit: {
                    submitCodexSurface(surface)
                }
            )
            .allowsHitTesting(false)
        )
        .onAppear {
            syncCodexApprovalInteraction(with: surface)
        }
        .onChange(of: surface) { _, updatedSurface in
            syncCodexApprovalInteraction(with: updatedSurface)
        }
    }

    private func codexSurfaceDetailHeader(
        _ surface: CodexActionableSurface,
        presentation: CodexApprovalDetailPresentation
    ) -> some View {
        HStack(alignment: .center, spacing: CodexApprovalCompactLayout.headerSpacing) {
            minimalBackButton

            if let summaryText = presentation.summaryText {
                Text(AppStrings.codexSurfaceSummary(summaryText, language: settingsStore.interfaceLanguage))
                    .font(.system(
                        size: CodexApprovalCompactLayout.headerSummaryFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(CodexApprovalCompactLayout.headerSummaryLineLimit)
                    .minimumScaleFactor(0.86)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            codexSurfaceActionButtons(surface)
        }
        .frame(maxWidth: .infinity, minHeight: CodexApprovalCompactLayout.headerButtonSize)
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

    private func codexSurfaceCard(
        _ surface: CodexActionableSurface,
        presentation: CodexApprovalDetailPresentation
    ) -> some View {
        codexApprovalPrimaryColumn(surface, presentation: presentation)
    }

    private func codexApprovalPrimaryColumn(
        _ surface: CodexActionableSurface,
        presentation: CodexApprovalDetailPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: CodexApprovalCompactLayout.primaryColumnSpacing) {
            AIPluginApprovalCommandView(
                text: AppStrings.codexSurfaceSummary(presentation.commandText, language: settingsStore.interfaceLanguage),
                compact: true
            )
            codexSurfaceControls(surface)
        }
    }

    private func codexSurfaceActionButtons(_ surface: CodexActionableSurface) -> some View {
        AIPluginCodexSurfaceActionButtons(
            surface: surface,
            focusedTarget: interactionState?.focusedTarget,
            onFocus: { target in
                focusCodexApproval(target, surface: surface)
            },
            onCancel: {
                focusCodexApproval(.cancel, surface: surface)
                onAction(.cancel)
            },
            onSubmit: {
                focusCodexApproval(.submit, surface: surface)
                submitCodexSurface(surface)
            }
        )
    }

    @ViewBuilder
    private func codexSurfaceControls(_ surface: CodexActionableSurface) -> some View {
        if surface.options.isEmpty == false || surface.textInput != nil {
            VStack(alignment: .leading, spacing: CodexApprovalCompactLayout.controlsSpacing) {
                let feedbackOptionID = CodexApprovalInteractionState.feedbackOptionID(for: surface)
                let standardOptions = surface.options.filter { $0.id != feedbackOptionID }
                let feedbackOption = feedbackOptionID.flatMap { optionID in
                    surface.options.first(where: { $0.id == optionID })
                }

                if standardOptions.isEmpty == false {
                    VStack(alignment: .leading, spacing: CodexApprovalCompactLayout.optionStackSpacing) {
                        ForEach(standardOptions) { option in
                            codexSurfaceOptionRow(option, surface: surface)
                        }
                    }
                }

                if let textInput = surface.textInput {
                    if let feedbackOption {
                        codexSurfaceFeedbackInput(textInput, option: feedbackOption, surface: surface)
                    } else {
                        codexSurfaceStandaloneTextInput(
                            textInput,
                            surface: surface,
                            index: surface.options.count + 1
                        )
                    }
                }
            }
        }
    }

    private func codexSurfaceOptionRow(_ option: CodexSurfaceOption, surface: CodexActionableSurface) -> some View {
        let isSelected = interactionState?.isOptionSelected(option.id, in: surface) ?? option.isSelected

        return AIPluginCodexSurfaceOptionRow(
            option: option,
            isSelected: isSelected,
            onActivate: {
                activateCodexApprovalOption(option.id, surface: surface)
            }
        )
    }

    private func codexSurfaceFeedbackInput(
        _ textInput: CodexSurfaceTextInput,
        option: CodexSurfaceOption,
        surface: CodexActionableSurface
    ) -> some View {
        let focusTarget = CodexApprovalFocusTarget.textInput(optionID: option.id)
        let isFocused = interactionState?.focusedTarget == focusTarget
        let presentation = CodexApprovalTextInputPresentation.feedback(
            textInput: textInput,
            option: option,
            language: settingsStore.interfaceLanguage
        )

        return codexSurfaceTextInput(
            textInput,
            surface: surface,
            focusTarget: focusTarget,
            presentation: presentation,
            isFocused: isFocused
        )
    }

    private func codexSurfaceStandaloneTextInput(
        _ textInput: CodexSurfaceTextInput,
        surface: CodexActionableSurface,
        index: Int
    ) -> some View {
        let focusTarget = CodexApprovalFocusTarget.textInput(optionID: nil)
        let isFocused = interactionState?.focusedTarget == focusTarget
        let presentation = CodexApprovalTextInputPresentation.standalone(
            textInput: textInput,
            index: index,
            language: settingsStore.interfaceLanguage
        )

        return codexSurfaceTextInput(
            textInput,
            surface: surface,
            focusTarget: focusTarget,
            presentation: presentation,
            isFocused: isFocused
        )
    }

    private func codexSurfaceTextInput(
        _ textInput: CodexSurfaceTextInput,
        surface: CodexActionableSurface,
        focusTarget: CodexApprovalFocusTarget,
        presentation: CodexApprovalTextInputPresentation,
        isFocused: Bool
    ) -> some View {
        AIPluginCodexSurfaceTextInputField(
            textInput: textInput,
            presentation: presentation,
            text: codexTextBinding(for: surface),
            isFocused: isFocused,
            contentHeight: textInputContentHeight,
            font: codexTextInputFont,
            isEditable: textInput.isEditable,
            onFocus: {
                focusCodexApproval(focusTarget, surface: surface)
            },
            onSubmit: {
                submitCodexSurface(surface)
            },
            onMoveUpBoundary: {
                moveCodexApprovalFocusFromTextInput(towardStart: true, surface: surface)
            },
            onMoveDownBoundary: {
                moveCodexApprovalFocusFromTextInput(towardStart: false, surface: surface)
            },
            onContentHeightChange: { contentHeight in
                textInputContentHeight = contentHeight
            }
        )
    }

    private func codexTextBinding(for surface: CodexActionableSurface) -> Binding<String> {
        Binding(
            get: {
                currentCodexTextDraft(for: surface)
            },
            set: { newValue in
                textDraftSurfaceID = surface.id
                textDraft = newValue
            }
        )
    }

    private func syncCodexApprovalInteraction(with surface: CodexActionableSurface) {
        if var existing = interactionState {
            existing.sync(surface: surface)
            interactionState = existing
        } else {
            interactionState = CodexApprovalInteractionState(surface: surface)
        }
        syncCodexTextDraft(with: surface)
    }

    private func focusCodexApproval(_ target: CodexApprovalFocusTarget, surface: CodexActionableSurface) {
        var state = interactionState ?? CodexApprovalInteractionState(surface: surface)
        _ = state.focus(target, surface: surface)
        interactionState = state
    }

    private func activateCodexApprovalOption(_ optionID: String, surface: CodexActionableSurface) {
        var state = interactionState ?? CodexApprovalInteractionState(surface: surface)
        let selectedOptionID = state.activateOption(optionID, surface: surface)
        interactionState = state

        guard let selectedOptionID else {
            return
        }

        onSelectOption(selectedOptionID)

        let feedbackOptionID = CodexApprovalInteractionState.feedbackOptionID(for: surface)
        if optionID != feedbackOptionID {
            submitCodexSurface(surface)
        }
    }

    private func moveCodexApprovalFocusUp(surface: CodexActionableSurface) {
        var state = interactionState ?? CodexApprovalInteractionState(surface: surface)
        _ = state.moveUp(surface: surface)
        interactionState = state
    }

    private func moveCodexApprovalFocusDown(surface: CodexActionableSurface) {
        var state = interactionState ?? CodexApprovalInteractionState(surface: surface)
        _ = state.moveDown(surface: surface)
        interactionState = state
    }

    private func moveCodexApprovalFocusFromTextInput(
        towardStart: Bool,
        surface: CodexActionableSurface
    ) {
        var state = interactionState ?? CodexApprovalInteractionState(surface: surface)
        guard let focusedTarget = state.focusedTarget,
              case .textInput = focusedTarget
        else {
            if towardStart {
                _ = state.moveUp(surface: surface)
            } else {
                _ = state.moveDown(surface: surface)
            }
            interactionState = state
            return
        }

        let nextTarget = state.adjacentTarget(
            from: focusedTarget,
            delta: towardStart ? -1 : 1,
            surface: surface
        )
        _ = state.focus(nextTarget, surface: surface)
        interactionState = state
    }

    private func syncCodexApprovalStateToSurface(surface: CodexActionableSurface) {
        if let optionID = interactionState?.selectedOptionIDToSync(in: surface),
           surface.options.first(where: { $0.id == optionID })?.isSelected != true {
            onSelectOption(optionID)
        }

        if surface.textInput != nil {
            let draftText = currentCodexTextDraft(for: surface)
            if draftText != (surface.textInput?.text ?? "") {
                onUpdateText(draftText)
            }
        }
    }

    private func submitCodexSurface(_ surface: CodexActionableSurface) {
        let state = interactionState ?? CodexApprovalInteractionState(surface: surface)

        if state.submitIntent(in: surface) == .cancel {
            onAction(.cancel)
            return
        }

        syncCodexApprovalStateToSurface(surface: surface)
        onAction(.primary)
    }

    private func syncCodexTextDraft(with surface: CodexActionableSurface) {
        guard textDraftSurfaceID != surface.id else {
            return
        }

        textDraftSurfaceID = surface.id
        textDraft = surface.textInput?.text ?? ""
    }

    private func currentCodexTextDraft(for surface: CodexActionableSurface) -> String {
        if textDraftSurfaceID == surface.id {
            return textDraft
        }

        return surface.textInput?.text ?? ""
    }

}
