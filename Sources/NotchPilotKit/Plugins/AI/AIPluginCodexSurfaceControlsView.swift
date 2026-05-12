import AppKit
import SwiftUI

struct AIPluginCodexSurfaceActionButtons: View {
    let surface: CodexActionableSurface
    let focusedTarget: CodexApprovalFocusTarget?
    let onFocus: (CodexApprovalFocusTarget) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void

    @ObservedObject private var settingsStore = SettingsStore.shared

    var body: some View {
        let cancelFocused = focusedTarget == .cancel
        let submitFocused = focusedTarget == .submit

        HStack(spacing: CodexApprovalCompactLayout.actionSpacing) {
            Button {
                onFocus(.cancel)
                onCancel()
            } label: {
                Text(AppStrings.codexButtonTitle(surface.cancelButtonTitle, language: settingsStore.interfaceLanguage))
                    .font(.system(
                        size: CodexApprovalCompactLayout.actionFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, CodexApprovalCompactLayout.actionHorizontalPadding)
                    .padding(.vertical, CodexApprovalCompactLayout.actionVerticalPadding)
                    .background(
                        Capsule(style: .continuous)
                            .fill(cancelFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(cancelFocused ? 0.18 : 0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button {
                onFocus(.submit)
                onSubmit()
            } label: {
                Text(AppStrings.codexButtonTitle(surface.primaryButtonTitle, language: settingsStore.interfaceLanguage))
                    .font(.system(
                        size: CodexApprovalCompactLayout.actionFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, CodexApprovalCompactLayout.actionHorizontalPadding + 1)
                    .padding(.vertical, CodexApprovalCompactLayout.actionVerticalPadding)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        NotchPilotTheme.codex,
                                        NotchPilotTheme.codex.opacity(0.72),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(submitFocused ? 0.24 : 0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

struct AIPluginCodexSurfaceOptionRow: View {
    let option: CodexSurfaceOption
    let isSelected: Bool
    let onActivate: () -> Void

    @ObservedObject private var settingsStore = SettingsStore.shared

    var body: some View {
        Button {
            onActivate()
        } label: {
            HStack(alignment: .center, spacing: CodexApprovalCompactLayout.optionContentSpacing) {
                Text("\(option.index)")
                    .font(.system(
                        size: CodexApprovalCompactLayout.optionIndexFontSize,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(isSelected ? .white : NotchPilotTheme.islandTextSecondary)
                    .frame(
                        width: CodexApprovalCompactLayout.optionIndexSize,
                        height: CodexApprovalCompactLayout.optionIndexSize
                    )
                    .background(
                        Circle()
                            .fill(
                                isSelected
                                    ? NotchPilotTheme.codex.opacity(0.95)
                                    : Color.white.opacity(0.08)
                            )
                    )

                Text(AppStrings.codexOptionTitle(option.title, language: settingsStore.interfaceLanguage))
                    .font(.system(
                        size: CodexApprovalCompactLayout.optionTitleFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(CodexApprovalCompactLayout.optionLineLimit)
                    .minimumScaleFactor(0.86)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                }
            }
            .padding(.horizontal, CodexApprovalCompactLayout.optionHorizontalPadding)
            .padding(.vertical, CodexApprovalCompactLayout.optionVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: CodexApprovalCompactLayout.optionCornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    NotchPilotTheme.codex.opacity(0.12),
                                    NotchPilotTheme.codex.opacity(0.04),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(0.03),
                                    Color.white.opacity(0.015),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: CodexApprovalCompactLayout.optionCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? NotchPilotTheme.codex.opacity(0.2) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct AIPluginCodexSurfaceTextInputField: View {
    let textInput: CodexSurfaceTextInput
    let presentation: CodexApprovalTextInputPresentation
    let text: Binding<String>
    let isFocused: Bool
    let contentHeight: CGFloat
    let font: NSFont
    let isEditable: Bool
    let onFocus: () -> Void
    let onSubmit: () -> Void
    let onMoveUpBoundary: () -> Void
    let onMoveDownBoundary: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    var body: some View {
        let sizing = CodexApprovalTextInputSizing(
            lineHeight: font.lineHeight,
            verticalPadding: CodexApprovalCompactLayout.textInputVerticalPadding
        )
        let leadingInset: CGFloat = presentation.indexPlacement == .insideFieldLeading
            ? CodexApprovalCompactLayout.textInputLeadingInset
            : 0

        return ZStack(alignment: .topLeading) {
            if presentation.indexPlacement == .insideFieldLeading {
                Text(presentation.indexText)
                    .font(.system(
                        size: CodexApprovalCompactLayout.textInputFontSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, CodexApprovalCompactLayout.textInputIndexLeadingPadding)
                    .padding(.top, CodexApprovalCompactLayout.textInputIndexTopPadding)
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .topLeading) {
                CodexApprovalTextEditor(
                    text: text,
                    isEditable: isEditable,
                    isFocused: isFocused,
                    font: font,
                    onFocus: onFocus,
                    onSubmit: onSubmit,
                    onMoveUpBoundary: onMoveUpBoundary,
                    onMoveDownBoundary: onMoveDownBoundary,
                    onContentHeightChange: onContentHeightChange
                )
                .padding(.leading, leadingInset)
                .frame(height: sizing.height(forContentHeight: contentHeight))
                .background(
                    RoundedRectangle(
                        cornerRadius: CodexApprovalCompactLayout.textInputCornerRadius,
                        style: .continuous
                    )
                        .fill(Color.white.opacity(isFocused ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: CodexApprovalCompactLayout.textInputCornerRadius,
                        style: .continuous
                    )
                        .strokeBorder(
                            isFocused ? NotchPilotTheme.codex.opacity(0.48) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .disabled(isEditable == false)

                if isFocused == false,
                   text.wrappedValue.isEmpty,
                   presentation.placeholder.isEmpty == false {
                    Text(presentation.placeholder)
                        .font(.system(
                            size: CodexApprovalCompactLayout.textInputFontSize,
                            weight: .medium,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.leading, CodexApprovalCompactLayout.placeholderHorizontalPadding + leadingInset)
                        .padding(.trailing, CodexApprovalCompactLayout.placeholderHorizontalPadding)
                        .padding(.vertical, CodexApprovalCompactLayout.placeholderVerticalPadding)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
    }
}
