import ApplicationServices
import Foundation

private let axWebAreaRole = "AXWebArea"
private let axNavigationLandmarkSubrole = "AXLandmarkNavigation"

struct CodexDesktopAXNode: Equatable, Sendable {
    let id: String
    let role: String
    let subrole: String?
    let title: String?
    let description: String?
    let value: String?
    let selected: Bool?
    let isValueSettable: Bool?
    let isEnabled: Bool
    let children: [CodexDesktopAXNode]
}

struct CodexDesktopAXWindowSnapshot: Equatable, Sendable {
    let id: String
    let isFocused: Bool
    let root: CodexDesktopAXNode
}

struct CodexDesktopAXSnapshot: Equatable, Sendable {
    let pid: pid_t
    let windows: [CodexDesktopAXWindowSnapshot]
}

struct CodexDesktopAXInspection: Equatable, Sendable {
    let surface: CodexActionableSurface
    let primaryActionNodeID: String
    let cancelActionNodeID: String
    let textInputNodeID: String?
}

private struct CodexDesktopAXTraversalContext {
    let isInWebArea: Bool
    let isInNavigation: Bool

    static let root = CodexDesktopAXTraversalContext(
        isInWebArea: false,
        isInNavigation: false
    )

    func advancing(with node: CodexDesktopAXNode) -> CodexDesktopAXTraversalContext {
        CodexDesktopAXTraversalContext(
            isInWebArea: isInWebArea || node.role == axWebAreaRole,
            isInNavigation: isInNavigation || node.subrole == axNavigationLandmarkSubrole
        )
    }
}

private struct CodexDesktopAXInlineSurfaceCandidate {
    let node: CodexDesktopAXNode
    let score: Int
    let totalNodeCount: Int
}

struct CodexDesktopAXInspector {
    func inspect(snapshot: CodexDesktopAXSnapshot) -> CodexDesktopAXInspection? {
        let orderedWindows = snapshot.windows.sorted { lhs, rhs in
            if lhs.isFocused != rhs.isFocused {
                return lhs.isFocused
            }
            return lhs.id < rhs.id
        }

        for window in orderedWindows {
            if let inspection = bestRequestCard(in: window.root, pid: snapshot.pid) {
                return inspection
            }
        }

        return nil
    }

    private func inspect(
        requestCardNode: CodexDesktopAXNode,
        pid: pid_t
    ) -> CodexDesktopAXInspection? {
        let buttons = directEnabledButtons(in: requestCardNode)
        let options = extractOptions(in: requestCardNode)
        let textInput = extractTextInput(in: requestCardNode)
        guard buttons.count == 2,
              let cancelButton = buttons.first,
              let primaryButton = buttons.last,
              let summary = resolveRequestCardSummary(for: requestCardNode, buttons: buttons),
              textInput == nil || options.isEmpty == false
        else {
            return nil
        }

        let surfaceID = "codex-ax-\(pid)-\(requestCardNode.id)"

        return CodexDesktopAXInspection(
            surface: CodexActionableSurface(
                id: surfaceID,
                summary: summary,
                primaryButtonTitle: primaryButton.title ?? "Continue",
                cancelButtonTitle: cancelButton.title ?? "Cancel",
                options: options,
                textInput: textInput?.surfaceTextInput
            ),
            primaryActionNodeID: primaryButton.id,
            cancelActionNodeID: cancelButton.id,
            textInputNodeID: textInput?.nodeID
        )
    }

    private func resolveRequestCardSummary(
        for requestCardNode: CodexDesktopAXNode,
        buttons: [CodexDesktopAXNode]
    ) -> String? {
        let summaryLines = requestCardSummaryLines(for: requestCardNode, buttons: buttons)
        guard summaryLines.isEmpty == false else {
            return nil
        }

        return summaryLines.prefix(2).joined(separator: "\n")
    }

    private func requestCardSummaryLines(
        for requestCardNode: CodexDesktopAXNode,
        buttons: [CodexDesktopAXNode]
    ) -> [String] {
        let buttonTitles = Set(
            buttons.compactMap(\.title)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
        )

        var summaryLines: [String] = []
        for candidate in [
            requestCardNode.value,
            requestCardNode.description,
            requestCardNode.title,
        ] {
            guard let line = sanitizeSummaryLine(candidate, buttonTitles: buttonTitles) else {
                continue
            }
            summaryLines.append(line)
        }

        return summaryLines
    }

    private func sanitizeSummaryLine(_ value: String?, buttonTitles: Set<String>) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, buttonTitles.contains(trimmed) == false else {
            return nil
        }

        return trimmed
    }

    private func collectButtons(in node: CodexDesktopAXNode) -> [CodexDesktopAXNode] {
        var buttons: [CodexDesktopAXNode] = []
        if node.role == kAXButtonRole as String {
            buttons.append(node)
        }
        for child in node.children {
            buttons.append(contentsOf: collectButtons(in: child))
        }
        return buttons
    }

    private func directEnabledButtons(in node: CodexDesktopAXNode) -> [CodexDesktopAXNode] {
        node.children.filter { child in
            child.role == kAXButtonRole as String
                && child.isEnabled
                && [child.title, child.value, child.description].contains {
                    guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                        return false
                    }
                    return value.isEmpty == false
                }
        }
    }

    private func extractOptions(in node: CodexDesktopAXNode) -> [CodexSurfaceOption] {
        guard let radioGroup = firstDescendant(in: node, matching: { $0.role == "AXRadioGroup" }) else {
            return []
        }

        let radioButtons = collectNodes(in: radioGroup) { candidate in
            candidate.role == "AXRadioButton"
                && candidate.isEnabled
                && resolvedControlTitle(for: candidate)?.isEmpty == false
        }

        return radioButtons.enumerated().map { index, button in
            CodexSurfaceOption(
                id: button.id,
                index: index + 1,
                title: resolvedControlTitle(for: button) ?? "Option \(index + 1)",
                isSelected: button.selected ?? false
            )
        }
    }

    private func extractTextInput(in node: CodexDesktopAXNode) -> (surfaceTextInput: CodexSurfaceTextInput, nodeID: String)? {
        guard let inputNode = firstDescendant(in: node, matching: { candidate in
            ["AXTextArea", "AXTextField"].contains(candidate.role)
        }) else {
            return nil
        }

        return (
            surfaceTextInput: CodexSurfaceTextInput(
                title: nearestTextInputTitle(in: node, inputNodeID: inputNode.id),
                text: inputNode.value ?? "",
                isEditable: inputNode.isValueSettable ?? inputNode.isEnabled
            ),
            nodeID: inputNode.id
        )
    }

    private func bestRequestCard(in node: CodexDesktopAXNode, pid: pid_t) -> CodexDesktopAXInspection? {
        let candidates = collectRequestCardCandidates(in: node, context: .root)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.totalNodeCount != rhs.totalNodeCount {
                    return lhs.totalNodeCount < rhs.totalNodeCount
                }
                return lhs.node.id < rhs.node.id
            }

        for candidate in candidates {
            if let inspection = inspect(requestCardNode: candidate.node, pid: pid) {
                return inspection
            }
        }

        return nil
    }

    private func collectRequestCardCandidates(
        in node: CodexDesktopAXNode,
        context: CodexDesktopAXTraversalContext
    ) -> [CodexDesktopAXInlineSurfaceCandidate] {
        let currentContext = context.advancing(with: node)

        var candidates: [CodexDesktopAXInlineSurfaceCandidate] = []
        if let candidate = requestCardCandidate(for: node, context: currentContext) {
            candidates.append(candidate)
        }

        for child in node.children {
            candidates.append(contentsOf: collectRequestCardCandidates(in: child, context: currentContext))
        }

        return candidates
    }

    private func requestCardCandidate(
        for node: CodexDesktopAXNode,
        context: CodexDesktopAXTraversalContext
    ) -> CodexDesktopAXInlineSurfaceCandidate? {
        guard context.isInWebArea, context.isInNavigation == false else {
            return nil
        }

        guard node.role == kAXGroupRole as String else {
            return nil
        }

        let directButtons = directEnabledButtons(in: node)
        guard directButtons.count == 2 else {
            return nil
        }

        let allButtons = collectButtons(in: node).filter(\.isEnabled)
        guard allButtons.count == directButtons.count else {
            return nil
        }

        let summaryLines = requestCardSummaryLines(for: node, buttons: directButtons)
        guard summaryLines.isEmpty == false else {
            return nil
        }

        let totalNodeCount = countNodes(in: node)
        guard totalNodeCount <= 24 else {
            return nil
        }

        guard containsNavigationLandmark(in: node) == false else {
            return nil
        }

        guard containsDisallowedInteractiveContent(in: node) == false else {
            return nil
        }

        guard node.children.count <= 8 else {
            return nil
        }

        let hasContainerSummarySource =
            sanitizeSummaryLine(node.value, buttonTitles: Set<String>()) != nil
            || sanitizeSummaryLine(node.description, buttonTitles: Set<String>()) != nil
            || sanitizeSummaryLine(node.title, buttonTitles: Set<String>()) != nil
        guard hasContainerSummarySource else {
            return nil
        }

        var score = 0
        if sanitizeSummaryLine(node.value, buttonTitles: Set<String>()) != nil {
            score += 40
        }
        if node.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 8
        }
        if summaryLines.count >= 2 {
            score += 4
        }
        score += max(0, 16 - totalNodeCount)

        return CodexDesktopAXInlineSurfaceCandidate(
            node: node,
            score: score,
            totalNodeCount: totalNodeCount
        )
    }

    private func countNodes(in node: CodexDesktopAXNode) -> Int {
        1 + node.children.reduce(0) { partialResult, child in
            partialResult + countNodes(in: child)
        }
    }

    private func firstDescendant(
        in node: CodexDesktopAXNode,
        matching predicate: (CodexDesktopAXNode) -> Bool
    ) -> CodexDesktopAXNode? {
        if predicate(node) {
            return node
        }

        for child in node.children {
            if let match = firstDescendant(in: child, matching: predicate) {
                return match
            }
        }

        return nil
    }

    private func collectNodes(
        in node: CodexDesktopAXNode,
        matching predicate: (CodexDesktopAXNode) -> Bool
    ) -> [CodexDesktopAXNode] {
        var matches: [CodexDesktopAXNode] = []
        if predicate(node) {
            matches.append(node)
        }
        for child in node.children {
            matches.append(contentsOf: collectNodes(in: child, matching: predicate))
        }
        return matches
    }

    private func resolvedControlTitle(for node: CodexDesktopAXNode) -> String? {
        for candidate in [node.title, node.description, node.value] {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.isEmpty == false
            else {
                continue
            }
            return value
        }
        return nil
    }

    private func nearestTextInputTitle(in root: CodexDesktopAXNode, inputNodeID: String) -> String? {
        guard let path = path(to: inputNodeID, in: root),
              path.isEmpty == false
        else {
            return nil
        }

        let parentPath = Array(path.dropLast())
        guard let parent = node(at: parentPath, in: root),
              let inputIndex = parent.children.firstIndex(where: { $0.id == inputNodeID })
        else {
            return nil
        }

        if inputIndex > 0 {
            for sibling in parent.children[..<inputIndex].reversed() {
                if let title = trailingStaticText(in: sibling) {
                    return title
                }
            }
        }

        return nil
    }

    private func trailingStaticText(in node: CodexDesktopAXNode) -> String? {
        if node.role == kAXStaticTextRole as String,
           let title = resolvedControlTitle(for: node) {
            return title
        }

        for child in node.children.reversed() {
            if let title = trailingStaticText(in: child) {
                return title
            }
        }

        return nil
    }

    private func path(to nodeID: String, in node: CodexDesktopAXNode) -> [Int]? {
        if node.id == nodeID {
            return []
        }

        for (index, child) in node.children.enumerated() {
            if let childPath = path(to: nodeID, in: child) {
                return [index] + childPath
            }
        }

        return nil
    }

    private func node(at path: [Int], in root: CodexDesktopAXNode) -> CodexDesktopAXNode? {
        var current = root
        for index in path {
            guard current.children.indices.contains(index) else {
                return nil
            }
            current = current.children[index]
        }
        return current
    }

    private func containsDisallowedInteractiveContent(in node: CodexDesktopAXNode) -> Bool {
        if disallowedInlineSurfaceRoles.contains(node.role) {
            return true
        }

        for child in node.children where containsDisallowedInteractiveContent(in: child) {
            return true
        }

        return false
    }

    private func containsNavigationLandmark(in node: CodexDesktopAXNode) -> Bool {
        if node.subrole == axNavigationLandmarkSubrole {
            return true
        }

        for child in node.children where containsNavigationLandmark(in: child) {
            return true
        }

        return false
    }
}

private let disallowedInlineSurfaceRoles: Set<String> = [
    "AXCheckBox",
    "AXComboBox",
    "AXList",
    "AXOutline",
    "AXPopUpButton",
    "AXSearchField",
    "AXSlider",
    "AXTable",
]
