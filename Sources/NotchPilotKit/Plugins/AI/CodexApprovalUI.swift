import AppKit
import SwiftUI

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

        targets.append(.cancel)
        targets.append(.submit)
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

struct CodexApprovalTextInputSizing: Equatable {
    let lineHeight: CGFloat
    let verticalPadding: CGFloat

    var minimumHeight: CGFloat {
        (lineHeight * 2) + verticalPadding
    }

    var maximumHeight: CGFloat {
        (lineHeight * 4) + verticalPadding
    }

    func height(forContentHeight contentHeight: CGFloat) -> CGFloat {
        min(max(contentHeight + verticalPadding, minimumHeight), maximumHeight)
    }
}

enum CodexApprovalCompactLayout {
    static let detailSpacing: CGFloat = 6
    static let headerSpacing: CGFloat = 7
    static let headerButtonSize: CGFloat = 24
    static let headerSummaryFontSize: CGFloat = 13
    static let headerSummaryLineHeight: CGFloat = 16
    static let headerSummaryLineLimit = 2

    static let primaryColumnSpacing: CGFloat = 6
    static let commandFontSize: CGFloat = 11
    static let commandLineHeight: CGFloat = 14
    static let commandLineLimit = 2
    static let commandHorizontalPadding: CGFloat = 8
    static let commandVerticalPadding: CGFloat = 5
    static let commandCornerRadius: CGFloat = 8

    static let controlsSpacing: CGFloat = 6
    static let optionStackSpacing: CGFloat = 4
    static let optionContentSpacing: CGFloat = 8
    static let optionIndexSize: CGFloat = 20
    static let optionIndexFontSize: CGFloat = 10
    static let optionTitleFontSize: CGFloat = 11
    static let optionLineHeight: CGFloat = 14
    static let optionLineLimit = 2
    static let optionHorizontalPadding: CGFloat = 10
    static let optionVerticalPadding: CGFloat = 5
    static let optionCornerRadius: CGFloat = 8

    static let actionSpacing: CGFloat = 6
    static let actionFontSize: CGFloat = 10
    static let actionHorizontalPadding: CGFloat = 9
    static let actionVerticalPadding: CGFloat = 5

    static let textInputFontSize: CGFloat = 11
    static let textInputLineHeight: CGFloat = 14
    static let textInputVerticalPadding: CGFloat = 8
    static let textInputLeadingInset: CGFloat = 24
    static let textInputIndexLeadingPadding: CGFloat = 9
    static let textInputIndexTopPadding: CGFloat = 8
    static let textInputCornerRadius: CGFloat = 8
    static let placeholderHorizontalPadding: CGFloat = 9
    static let placeholderVerticalPadding: CGFloat = 8

    static var commandSingleLineHeight: CGFloat {
        commandLineHeight + (commandVerticalPadding * 2)
    }

    static var optionRowHeight: CGFloat {
        max(optionIndexSize, optionLineHeight) + (optionVerticalPadding * 2)
    }

    static var textInputMinimumHeight: CGFloat {
        CodexApprovalTextInputSizing(
            lineHeight: textInputLineHeight,
            verticalPadding: textInputVerticalPadding
        ).minimumHeight
    }

    static func estimatedDetailHeight(
        optionCount: Int,
        commandLineCount: Int,
        includesTextInput: Bool,
        headerLineCount: Int
    ) -> CGFloat {
        let headerLines = max(1, min(headerLineCount, headerSummaryLineLimit))
        let headerHeight = max(headerButtonSize, CGFloat(headerLines) * headerSummaryLineHeight)
        let commandLines = max(1, min(commandLineCount, commandLineLimit))
        let commandHeight = CGFloat(commandLines) * commandLineHeight + (commandVerticalPadding * 2)

        let safeOptionCount = max(0, optionCount)
        let optionsHeight = safeOptionCount == 0
            ? 0
            : CGFloat(safeOptionCount) * optionRowHeight
                + CGFloat(max(0, safeOptionCount - 1)) * optionStackSpacing
        let inputHeight = includesTextInput ? textInputMinimumHeight : 0
        let controlGroupCount = (safeOptionCount > 0 ? 1 : 0) + (includesTextInput ? 1 : 0)
        let controlsHeight =
            optionsHeight
            + inputHeight
            + CGFloat(max(0, controlGroupCount - 1)) * controlsSpacing

        return headerHeight
            + detailSpacing
            + commandHeight
            + (controlsHeight > 0 ? primaryColumnSpacing + controlsHeight : 0)
    }
}

enum CodexApprovalTextBoundary {
    static func shouldMoveOutOfTextView(
        text: String,
        selectedRange: NSRange,
        towardStart: Bool
    ) -> Bool {
        shouldMoveOutOfTextView(
            selectedRange: selectedRange,
            towardStart: towardStart,
            lineRanges: logicalLineRanges(for: text),
            textLength: (text as NSString).length
        )
    }

    static func shouldMoveOutOfTextView(
        selectedRange: NSRange,
        towardStart: Bool,
        lineRanges: [NSRange],
        textLength: Int
    ) -> Bool {
        guard selectedRange.length == 0 else {
            return false
        }

        guard lineRanges.isEmpty == false else {
            return true
        }

        let clampedLocation = min(selectedRange.location, textLength)
        let currentLineIndex: Int

        if clampedLocation >= textLength {
            currentLineIndex = lineRanges.count - 1
        } else if let matchingLineIndex = lineRanges.firstIndex(where: { range in
            clampedLocation >= range.location && clampedLocation < NSMaxRange(range)
        }) {
            currentLineIndex = matchingLineIndex
        } else {
            let lastRange = lineRanges.last ?? NSRange(location: 0, length: 0)
            return towardStart
                ? clampedLocation <= lineRanges.first?.location ?? 0
                : clampedLocation >= NSMaxRange(lastRange)
        }

        return towardStart
            ? currentLineIndex == 0
            : currentLineIndex == lineRanges.count - 1
    }

    private static func logicalLineRanges(for text: String) -> [NSRange] {
        let nsText = text as NSString
        let fullLength = nsText.length

        guard fullLength > 0 else {
            return [NSRange(location: 0, length: 0)]
        }

        var ranges: [NSRange] = []
        var location = 0

        while location < fullLength {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(lineRange)
            let nextLocation = NSMaxRange(lineRange)
            if nextLocation <= location || nextLocation >= fullLength {
                break
            }
            location = nextLocation
        }

        return ranges
    }
}

enum CodexApprovalKeyCommand: Equatable {
    case moveUp
    case moveDown
    case submit

    static func resolve(
        event: NSEvent,
        isEnabled: Bool,
        focusedTarget: CodexApprovalFocusTarget?
    ) -> CodexApprovalKeyCommand? {
        guard isEnabled else {
            return nil
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return nil
        }

        if case .textInput? = focusedTarget {
            return nil
        }

        switch event.keyCode {
        case 126:
            return .moveUp
        case 125:
            return .moveDown
        case 36, 76:
            return .submit
        default:
            return nil
        }
    }
}

struct CodexApprovalKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let focusedTarget: CodexApprovalFocusTarget?
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> CodexApprovalKeyMonitorView {
        let view = CodexApprovalKeyMonitorView()
        view.update(
            isEnabled: isEnabled,
            focusedTarget: focusedTarget,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onSubmit: onSubmit
        )
        return view
    }

    func updateNSView(_ view: CodexApprovalKeyMonitorView, context: Context) {
        view.update(
            isEnabled: isEnabled,
            focusedTarget: focusedTarget,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onSubmit: onSubmit
        )
    }
}

@MainActor
final class CodexApprovalKeyMonitorView: NSView {
    private var monitor: Any?
    private var isEnabled = false
    private var focusedTarget: CodexApprovalFocusTarget?
    private var onMoveUp: (() -> Void)?
    private var onMoveDown: (() -> Void)?
    private var onSubmit: (() -> Void)?

    func update(
        isEnabled: Bool,
        focusedTarget: CodexApprovalFocusTarget?,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.focusedTarget = focusedTarget
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onSubmit = onSubmit

        if isEnabled {
            installMonitorIfNeeded()
            refreshKeyboardRouting(for: window)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.refreshKeyboardRouting(for: self.window)
            }
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if isEnabled {
            installMonitorIfNeeded()
            refreshKeyboardRouting(for: window)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        super.viewWillMove(toWindow: newWindow)
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handle(event: event) ? nil : event
        }
    }

    override func keyDown(with event: NSEvent) {
        if handle(event: event) == false {
            super.keyDown(with: event)
        }
    }

    private func handle(event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true else {
            return false
        }

        switch CodexApprovalKeyCommand.resolve(
            event: event,
            isEnabled: isEnabled,
            focusedTarget: focusedTarget
        ) {
        case .moveUp:
            onMoveUp?()
            return true
        case .moveDown:
            onMoveDown?()
            return true
        case .submit:
            onSubmit?()
            return true
        case nil:
            return false
        }
    }

    private func refreshKeyboardRouting(for window: NSWindow?) {
        guard isEnabled else {
            return
        }

        activateWindowForKeyboardInput(window)

        guard let window else {
            return
        }

        if case .textInput? = focusedTarget {
            if window.firstResponder === self {
                window.makeFirstResponder(nil)
            }
        } else if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }
}

struct CodexApprovalTextEditor: NSViewRepresentable {
    @Binding var text: String

    let isEditable: Bool
    let isFocused: Bool
    let font: NSFont
    let onFocus: () -> Void
    let onSubmit: () -> Void
    let onMoveUpBoundary: () -> Void
    let onMoveDownBoundary: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = CodexApprovalNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.font = font
        textView.string = text
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = .white
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = CGSize(width: 0, height: 0)
        textView.textContainer?.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.boundaryDelegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.reportContentHeight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        context.coordinator.parent = self
        textView.isEditable = isEditable
        textView.font = font

        if textView.string != text {
            textView.string = text
            context.coordinator.reportContentHeight()
        }

        if isFocused {
            activateWindowForKeyboardInput(scrollView.window)
            if scrollView.window?.firstResponder !== textView {
                scrollView.window?.makeFirstResponder(textView)
            }
            DispatchQueue.main.async {
                activateWindowForKeyboardInput(scrollView.window)
                if scrollView.window?.firstResponder !== textView {
                    scrollView.window?.makeFirstResponder(textView)
                }
            }
        } else if scrollView.window?.firstResponder === textView {
            scrollView.window?.makeFirstResponder(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, CodexApprovalNSTextViewBoundaryDelegate {
        var parent: CodexApprovalTextEditor
        fileprivate weak var textView: CodexApprovalNSTextView?

        init(parent: CodexApprovalTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else {
                return
            }

            let nextText = textView.string
            if parent.text != nextText {
                parent.text = nextText
            }
            reportContentHeight()
        }

        func textViewDidBecomeFirstResponder() {
            parent.onFocus()
        }

        func textViewDidRequestSubmit() {
            parent.onSubmit()
        }

        func textViewDidRequestMoveUpBoundary() {
            parent.onMoveUpBoundary()
            releaseTextViewFirstResponderIfNeeded()
        }

        func textViewDidRequestMoveDownBoundary() {
            parent.onMoveDownBoundary()
            releaseTextViewFirstResponderIfNeeded()
        }

        func textViewDidMoveWithinText() {}

        func reportContentHeight() {
            guard let textView else {
                return
            }

            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else {
                let fallbackHeight = textView.font?.lineHeight ?? 20
                parent.onContentHeightChange(fallbackHeight)
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let fallbackLineHeight = textView.font?.lineHeight ?? 20
            parent.onContentHeightChange(max(usedHeight, fallbackLineHeight))
        }

        private func releaseTextViewFirstResponderIfNeeded() {
            guard let textView else {
                return
            }

            activateWindowForKeyboardInput(textView.window)
            handOffFirstResponder(from: textView)

            DispatchQueue.main.async {
                activateWindowForKeyboardInput(textView.window)
                self.handOffFirstResponder(from: textView)
            }
        }

        private func handOffFirstResponder(from textView: NSTextView) {
            guard let window = textView.window else {
                return
            }

            guard window.firstResponder === textView else {
                if window.firstResponder == nil,
                   let keyMonitorView = window.codexApprovalKeyMonitorView {
                    window.makeFirstResponder(keyMonitorView)
                }
                return
            }

            if let keyMonitorView = window.codexApprovalKeyMonitorView {
                window.makeFirstResponder(keyMonitorView)
            } else {
                window.makeFirstResponder(nil)
            }
        }
    }
}

@MainActor
protocol CodexApprovalNSTextViewBoundaryDelegate: AnyObject {
    func textViewDidBecomeFirstResponder()
    func textViewDidRequestSubmit()
    func textViewDidRequestMoveUpBoundary()
    func textViewDidRequestMoveDownBoundary()
    func textViewDidMoveWithinText()
}

@MainActor
final class CodexApprovalNSTextView: NSTextView {
    weak var boundaryDelegate: CodexApprovalNSTextViewBoundaryDelegate?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            boundaryDelegate?.textViewDidBecomeFirstResponder()
        }
        return became
    }

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasOnlyShift = modifiers == [.shift]
        let hasNoModifiers = modifiers.isEmpty

        switch event.keyCode {
        case 36, 76:
            if hasOnlyShift {
                super.keyDown(with: event)
                return
            }
            if hasNoModifiers {
                boundaryDelegate?.textViewDidRequestSubmit()
                return
            }
        default:
            break
        }

        super.keyDown(with: event)
    }

    override func moveUp(_ sender: Any?) {
        if shouldMoveOutOfTextView(towardStart: true) {
            boundaryDelegate?.textViewDidRequestMoveUpBoundary()
            return
        }

        super.moveUp(sender)
        boundaryDelegate?.textViewDidMoveWithinText()
    }

    override func moveDown(_ sender: Any?) {
        if shouldMoveOutOfTextView(towardStart: false) {
            boundaryDelegate?.textViewDidRequestMoveDownBoundary()
            return
        }

        super.moveDown(sender)
        boundaryDelegate?.textViewDidMoveWithinText()
    }

    private func shouldMoveOutOfTextView(towardStart: Bool) -> Bool {
        guard selectedRanges.count == 1
        else {
            return false
        }

        if let lineRanges = visualLineRanges() {
            return CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                selectedRange: selectedRange(),
                towardStart: towardStart,
                lineRanges: lineRanges,
                textLength: (string as NSString).length
            )
        }

        return CodexApprovalTextBoundary.shouldMoveOutOfTextView(
            text: string,
            selectedRange: selectedRange(),
            towardStart: towardStart
        )
    }

    private func visualLineRanges() -> [NSRange]? {
        guard let layoutManager,
              let textContainer
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            return [NSRange(location: 0, length: 0)]
        }

        var ranges: [NSRange] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, fragmentGlyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: fragmentGlyphRange, actualGlyphRange: nil)
            ranges.append(characterRange)
        }
        return ranges.isEmpty ? nil : ranges
    }
}

extension NSFont {
    var lineHeight: CGFloat {
        ascender - descender + leading
    }
}

@MainActor
private func activateWindowForKeyboardInput(_ window: NSWindow?) {
    guard let window else {
        return
    }

    if NSApp.isActive == false {
        NSApp.activate(ignoringOtherApps: true)
    }

    if window.isKeyWindow == false {
        window.makeKeyAndOrderFront(nil)
    }
}

private extension NSWindow {
    var codexApprovalKeyMonitorView: CodexApprovalKeyMonitorView? {
        guard let contentView else {
            return nil
        }

        return findSubview(in: contentView)
    }

    private func findSubview(in view: NSView) -> CodexApprovalKeyMonitorView? {
        if let keyMonitorView = view as? CodexApprovalKeyMonitorView {
            return keyMonitorView
        }

        for subview in view.subviews {
            if let keyMonitorView = findSubview(in: subview) {
                return keyMonitorView
            }
        }

        return nil
    }
}
