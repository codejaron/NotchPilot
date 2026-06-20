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

    @ObservedObject private var generalSettings = SettingsStore.shared.general

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
                Text(AppStrings.codexSurfaceSummary(summaryText, language: generalSettings.interfaceLanguage))
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

            if surface.showsActionButtons {
                codexSurfaceActionButtons(surface)
            }
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
            if surface.fileChanges.isEmpty {
                AIPluginApprovalCommandView(
                    text: AppStrings.codexSurfaceSummary(presentation.commandText, language: generalSettings.interfaceLanguage),
                    compact: true
                )
            } else {
                codexFileChangeSection(surface, presentation: presentation)
            }
            codexSurfaceControls(surface)
        }
    }

    @ViewBuilder
    private func codexFileChangeSection(
        _ surface: CodexActionableSurface,
        presentation: CodexApprovalDetailPresentation
    ) -> some View {
        let caption = presentation.summaryText == nil
            ? AppStrings.codexSurfaceSummary(presentation.commandText, language: generalSettings.interfaceLanguage)
            : ""

        VStack(alignment: .leading, spacing: 5) {
            if caption.isEmpty == false {
                Text(caption)
                    .font(.system(
                        size: CodexApprovalCompactLayout.headerSummaryFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(CodexApprovalCompactLayout.headerSummaryLineLimit)
                    .minimumScaleFactor(0.86)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            codexFileChangeList(surface.fileChanges)
        }
    }

    private func codexFileChangeList(_ changes: [CodexFileChange]) -> some View {
        let maxVisible = 8
        let visible = Array(changes.prefix(maxVisible))
        let overflow = changes.count - visible.count

        return VStack(alignment: .leading, spacing: 3) {
            ForEach(visible) { change in
                codexFileChangeRow(change)
            }

            if overflow > 0 {
                Text(generalSettings.interfaceLanguage == .zhHans
                    ? "还有 \(overflow) 个文件"
                    : "+\(overflow) more files")
                    .font(.system(size: CodexApprovalCompactLayout.commandFontSize, weight: .medium))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary.opacity(0.55))
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CodexApprovalCompactLayout.commandHorizontalPadding)
        .padding(.vertical, CodexApprovalCompactLayout.commandVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: CodexApprovalCompactLayout.commandCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CodexApprovalCompactLayout.commandCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func codexFileChangeRow(_ change: CodexFileChange) -> some View {
        HStack(spacing: 6) {
            Text(codexFileChangeGlyph(change.kind))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(codexFileChangeTint(change.kind))
                .frame(width: 12, alignment: .center)

            Text(change.displayPath)
                .font(.system(
                    size: CodexApprovalCompactLayout.commandFontSize,
                    weight: .medium,
                    design: .monospaced
                ))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if change.addedLines > 0 {
                Text("+\(change.addedLines)")
                    .font(.system(
                        size: CodexApprovalCompactLayout.commandFontSize,
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .foregroundStyle(Color(red: 0.36, green: 0.78, blue: 0.45))
            }

            if change.removedLines > 0 {
                Text("-\(change.removedLines)")
                    .font(.system(
                        size: CodexApprovalCompactLayout.commandFontSize,
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .foregroundStyle(Color(red: 0.90, green: 0.40, blue: 0.42))
            }
        }
    }

    private func codexFileChangeGlyph(_ kind: CodexFileChange.Kind) -> String {
        switch kind {
        case .add:
            return "A"
        case .update:
            return "M"
        case .delete:
            return "D"
        case .move:
            return "R"
        }
    }

    private func codexFileChangeTint(_ kind: CodexFileChange.Kind) -> Color {
        switch kind {
        case .add:
            return Color(red: 0.36, green: 0.78, blue: 0.45)
        case .update:
            return Color(red: 0.55, green: 0.70, blue: 0.98)
        case .delete:
            return Color(red: 0.90, green: 0.40, blue: 0.42)
        case .move:
            return Color(red: 0.82, green: 0.66, blue: 0.40)
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
            language: generalSettings.interfaceLanguage
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
            language: generalSettings.interfaceLanguage
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
