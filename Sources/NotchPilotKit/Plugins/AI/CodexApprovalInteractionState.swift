import Foundation

enum CodexApprovalFocusTarget: Equatable {
    case option(id: String)
    case textInput(optionID: String?)
    case cancel
    case submit
}

enum CodexApprovalSubmitIntent: Equatable {
    case cancel
    case primary(selectedOptionID: String?)
}

struct CodexApprovalInteractionState: Equatable {
    private(set) var focusedTarget: CodexApprovalFocusTarget?
    private(set) var pendingSelectionTarget: CodexApprovalFocusTarget?

    init(surface: CodexActionableSurface) {
        pendingSelectionTarget = Self.surfaceSelectionTarget(for: surface)
        focusedTarget = Self.preferredTarget(for: surface, selectedTarget: pendingSelectionTarget)
    }

    mutating func sync(surface: CodexActionableSurface) {
        let targets = Self.orderedTargets(for: surface)
        if Self.isValidSelectionTarget(pendingSelectionTarget, for: surface) == false {
            pendingSelectionTarget = Self.surfaceSelectionTarget(for: surface)
        }

        if let focusedTarget, targets.contains(focusedTarget) {
            return
        }

        focusedTarget = Self.preferredTarget(for: surface, selectedTarget: pendingSelectionTarget)
    }

    mutating func focus(_ target: CodexApprovalFocusTarget?, surface: CodexActionableSurface) -> CodexApprovalFocusTarget? {
        let targets = Self.orderedTargets(for: surface)
        guard let target, targets.contains(target) else {
            focusedTarget = Self.preferredTarget(for: surface, selectedTarget: pendingSelectionTarget)
            return focusedTarget
        }

        focusedTarget = target
        updatePendingSelection(for: target)
        return focusedTarget
    }

    mutating func moveUp(surface: CodexActionableSurface) -> CodexApprovalFocusTarget? {
        move(delta: -1, surface: surface)
    }

    mutating func moveDown(surface: CodexActionableSurface) -> CodexApprovalFocusTarget? {
        move(delta: 1, surface: surface)
    }

    mutating func activateOption(_ optionID: String, surface: CodexActionableSurface) -> String? {
        _ = focus(.option(id: optionID), surface: surface)
        return selectedOptionIDToSync(in: surface)
    }

    func submitIntent(in surface: CodexActionableSurface) -> CodexApprovalSubmitIntent {
        if focusedTarget == .cancel {
            return .cancel
        }

        return .primary(selectedOptionID: selectedOptionIDToSync(in: surface))
    }

    func adjacentTarget(
        from target: CodexApprovalFocusTarget,
        delta: Int,
        surface: CodexActionableSurface
    ) -> CodexApprovalFocusTarget? {
        let targets = Self.orderedTargets(for: surface)
        guard let index = targets.firstIndex(of: target) else {
            return nil
        }

        let nextIndex = min(max(index + delta, 0), targets.count - 1)
        return targets[nextIndex]
    }

    private mutating func move(delta: Int, surface: CodexActionableSurface) -> CodexApprovalFocusTarget? {
        let targets = Self.orderedTargets(for: surface)
        guard targets.isEmpty == false else {
            focusedTarget = nil
            return nil
        }

        let current = focusedTarget ?? Self.preferredTarget(for: surface, selectedTarget: pendingSelectionTarget) ?? targets[0]
        let currentIndex = targets.firstIndex(of: current) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), targets.count - 1)
        focusedTarget = targets[nextIndex]
        updatePendingSelection(for: targets[nextIndex])
        return focusedTarget
    }

    func selectedOptionIDToSync(in surface: CodexActionableSurface) -> String? {
        switch effectiveSelectionTarget(in: surface) {
        case let .option(id):
            return id
        case let .textInput(optionID):
            if let optionID,
               surface.options.contains(where: { $0.id == optionID }) {
                return optionID
            }
            return nil
        case .cancel, .submit, nil:
            return nil
        }
    }

    func isOptionSelected(_ optionID: String, in surface: CodexActionableSurface) -> Bool {
        effectiveSelectionTarget(in: surface) == .option(id: optionID)
    }

    func isTextInputSelected(optionID: String?, in surface: CodexActionableSurface) -> Bool {
        effectiveSelectionTarget(in: surface) == .textInput(optionID: optionID)
    }

    static func orderedTargets(for surface: CodexActionableSurface) -> [CodexApprovalFocusTarget] {
        var targets = surface.options.map { option in
            CodexApprovalFocusTarget.option(id: option.id)
        }

        if let optionID = feedbackOptionID(for: surface) {
            targets.removeAll { $0 == .option(id: optionID) }
            targets.append(.textInput(optionID: optionID))
        } else if surface.textInput != nil {
            targets.append(.textInput(optionID: nil))
        }

        if surface.showsActionButtons {
            targets.append(.cancel)
            targets.append(.submit)
        }
        return targets
    }

    static func feedbackOptionID(for surface: CodexActionableSurface) -> String? {
        guard let attachedOptionID = surface.textInput?.attachedOptionID,
              surface.options.contains(where: { $0.id == attachedOptionID }) else {
            return nil
        }

        return attachedOptionID
    }

    private mutating func updatePendingSelection(for target: CodexApprovalFocusTarget?) {
        guard let target else {
            return
        }

        switch target {
        case .option, .textInput:
            pendingSelectionTarget = target
        case .cancel, .submit:
            break
        }
    }

    private static func preferredTarget(
        for surface: CodexActionableSurface,
        selectedTarget: CodexApprovalFocusTarget?
    ) -> CodexApprovalFocusTarget? {
        if isValidSelectionTarget(selectedTarget, for: surface) {
            return selectedTarget
        }

        return orderedTargets(for: surface).first
    }

    private func effectiveSelectionTarget(in surface: CodexActionableSurface) -> CodexApprovalFocusTarget? {
        if Self.isValidSelectionTarget(pendingSelectionTarget, for: surface) {
            return pendingSelectionTarget
        }

        return Self.surfaceSelectionTarget(for: surface)
    }

    private static func surfaceSelectionTarget(for surface: CodexActionableSurface) -> CodexApprovalFocusTarget? {
        if let selectedOptionID = surface.options.first(where: \.isSelected)?.id {
            if feedbackOptionID(for: surface) == selectedOptionID {
                return .textInput(optionID: selectedOptionID)
            }

            return .option(id: selectedOptionID)
        }

        if surface.textInput?.text.isEmpty == false {
            return .textInput(optionID: feedbackOptionID(for: surface))
        }

        return nil
    }

    private static func isValidSelectionTarget(
        _ target: CodexApprovalFocusTarget?,
        for surface: CodexActionableSurface
    ) -> Bool {
        guard let target else {
            return false
        }

        switch target {
        case let .option(id):
            return surface.options.contains(where: { $0.id == id })
        case let .textInput(optionID):
            guard surface.textInput != nil else {
                return false
            }
            return optionID == nil || feedbackOptionID(for: surface) == optionID
        case .cancel, .submit:
            return false
        }
    }
}
