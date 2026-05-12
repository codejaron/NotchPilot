import SwiftUI

struct AIPluginClaudeQuestionView: View {
    let approval: PendingApproval
    @Binding var questionSelections: [String: Set<String>]
    @Binding var questionTextAnswers: [String: String]
    let onRespond: (ApprovalAction) -> Void

    @ObservedObject private var settingsStore = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(approval.payload.claudeQuestions) { question in
                questionBlock(question)
            }

            HStack(spacing: 8) {
                Button {
                    submitSkip()
                } label: {
                    Text(AppStrings.text(.skip, language: settingsStore.interfaceLanguage))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    submitAnswers()
                } label: {
                    Text(AppStrings.text(.submit, language: settingsStore.interfaceLanguage))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    canSubmitAnswers
                                        ? NotchPilotTheme.claude.opacity(0.68)
                                        : Color.white.opacity(0.08)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(canSubmitAnswers == false)
            }
        }
        .onAppear {
            ensureQuestionDefaults()
        }
    }

    private func questionBlock(_ question: ClaudeUserQuestion) -> some View {
        let key = questionKey(question: question)
        let showsTextInput = question.options.isEmpty
            || selectedQuestionLabels(question: question).contains(where: isFreeformOption)

        return VStack(alignment: .leading, spacing: 8) {
            if let header = question.header, header.isEmpty == false {
                Text(header)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.claude.opacity(0.9))
                    .lineLimit(1)
            }

            Text(question.question)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if question.options.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(question.options) { option in
                        questionOptionRow(option, question: question)
                    }
                }
            }

            if showsTextInput {
                TextField(
                    "Type your own answer here",
                    text: Binding(
                        get: {
                            questionTextAnswers[key, default: ""]
                        },
                        set: { value in
                            questionTextAnswers[key] = value
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NotchPilotTheme.claude.opacity(0.28), lineWidth: 1)
                )
            }
        }
    }

    private func questionOptionRow(
        _ option: ClaudeQuestionOption,
        question: ClaudeUserQuestion
    ) -> some View {
        let isSelected = selectedQuestionLabels(question: question).contains(option.label)

        return Button {
            toggleQuestionOption(option.label, question: question)
        } label: {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? NotchPilotTheme.claude : NotchPilotTheme.islandTextSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let description = option.description, description.isEmpty == false {
                        Text(description)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? NotchPilotTheme.claude.opacity(0.12) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? NotchPilotTheme.claude.opacity(0.34) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func ensureQuestionDefaults() {
        for question in approval.payload.claudeQuestions {
            let key = questionKey(question: question)
            if questionSelections[key] == nil,
               let firstOption = question.options.first {
                questionSelections[key] = [firstOption.label]
            }
        }
    }

    private func toggleQuestionOption(
        _ label: String,
        question: ClaudeUserQuestion
    ) {
        let key = questionKey(question: question)
        var selections = questionSelections[key] ?? []

        if question.multiSelect {
            if selections.contains(label) {
                selections.remove(label)
            } else {
                selections.insert(label)
            }
        } else {
            selections = [label]
        }

        questionSelections[key] = selections
    }

    private func selectedQuestionLabels(question: ClaudeUserQuestion) -> Set<String> {
        questionSelections[questionKey(question: question)] ?? []
    }

    private func questionKey(question: ClaudeUserQuestion) -> String {
        "\(approval.requestID)::\(question.id)"
    }

    private func isFreeformOption(_ label: String) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "other" || normalized == "其他"
    }

    private var questionAnswers: [String: String] {
        approval.payload.claudeQuestions.reduce(into: [:]) { answers, question in
            let key = questionKey(question: question)
            let selected = selectedQuestionLabels(question: question)
            let selectedLabels = question.options.map(\.label).filter { selected.contains($0) }
            let textAnswer = questionTextAnswers[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let answerParts = selectedLabels.compactMap { label -> String? in
                if isFreeformOption(label), textAnswer.isEmpty == false {
                    return textAnswer
                }
                return label
            }
            let answer = answerParts.isEmpty ? textAnswer : answerParts.joined(separator: ", ")

            guard answer.isEmpty == false else {
                return
            }

            answers[question.question] = answer
        }
    }

    private var canSubmitAnswers: Bool {
        questionAnswers.count == approval.payload.claudeQuestions.count
    }

    private func submitAnswers() {
        let answers = questionAnswers
        guard answers.count == approval.payload.claudeQuestions.count else {
            return
        }

        let action = ApprovalAction(
            id: "claude-question-submit",
            title: AppStrings.text(.submit, language: settingsStore.interfaceLanguage),
            style: .primary,
            payload: .claude(
                ApprovalDecision(
                    behavior: .allow,
                    updatedInput: approval.payload.updatedInput(answering: answers)
                )
            )
        )
        onRespond(action)
    }

    private func submitSkip() {
        let action = ApprovalAction(
            id: "claude-question-skip",
            title: AppStrings.text(.skip, language: settingsStore.interfaceLanguage),
            style: .outline,
            payload: .claude(
                ApprovalDecision(
                    behavior: .deny,
                    feedbackText: "Skipped via NotchPilot"
                )
            )
        )
        onRespond(action)
    }
}
