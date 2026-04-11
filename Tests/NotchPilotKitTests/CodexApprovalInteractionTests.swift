import AppKit
import XCTest
@testable import NotchPilotKit

@MainActor
private final class CodexApprovalBoundaryRecorder: NSObject, CodexApprovalNSTextViewBoundaryDelegate {
    private(set) var moveUpBoundaryCount = 0
    private(set) var moveDownBoundaryCount = 0
    private(set) var moveWithinTextCount = 0

    func textViewDidBecomeFirstResponder() {}
    func textViewDidRequestSubmit() {}

    func textViewDidRequestMoveUpBoundary() {
        moveUpBoundaryCount += 1
    }

    func textViewDidRequestMoveDownBoundary() {
        moveDownBoundaryCount += 1
    }

    func textViewDidMoveWithinText() {
        moveWithinTextCount += 1
    }
}

final class CodexApprovalInteractionTests: XCTestCase {
    func testMoveDownAdvancesAcrossOptionsInputAndButtons() {
        let surface = makeSurface()
        var state = CodexApprovalInteractionState(surface: surface)

        XCTAssertEqual(state.focusedTarget, .option(id: "option-1"))
        XCTAssertEqual(state.moveDown(surface: surface), .option(id: "option-2"))
        XCTAssertEqual(state.moveDown(surface: surface), .textInput(optionID: "option-3"))
        XCTAssertEqual(state.moveDown(surface: surface), .cancel)
        XCTAssertEqual(state.moveDown(surface: surface), .submit)
        XCTAssertEqual(state.moveDown(surface: surface), .submit)
    }

    func testMoveUpReturnsFromSubmitToCancelThenInputAndOptions() {
        let surface = makeSurface()
        var state = CodexApprovalInteractionState(surface: surface)
        _ = state.moveDown(surface: surface)
        _ = state.moveDown(surface: surface)
        _ = state.moveDown(surface: surface)
        _ = state.moveDown(surface: surface)

        XCTAssertEqual(state.focusedTarget, .submit)
        XCTAssertEqual(state.moveUp(surface: surface), .cancel)
        XCTAssertEqual(state.moveUp(surface: surface), .textInput(optionID: "option-3"))
        XCTAssertEqual(state.moveUp(surface: surface), .option(id: "option-2"))
        XCTAssertEqual(state.moveUp(surface: surface), .option(id: "option-1"))
        XCTAssertEqual(state.moveUp(surface: surface), .option(id: "option-1"))
    }

    func testTextInputAdjacentTargetsMapToOptionTwoAndCancel() {
        let surface = makeSurface()
        let state = CodexApprovalInteractionState(surface: surface)
        let textInputTarget = CodexApprovalFocusTarget.textInput(optionID: "option-3")

        XCTAssertEqual(
            state.adjacentTarget(from: textInputTarget, delta: -1, surface: surface),
            .option(id: "option-2")
        )
        XCTAssertEqual(
            state.adjacentTarget(from: textInputTarget, delta: 1, surface: surface),
            .cancel
        )
    }

    func testInitialFocusUsesSelectedFeedbackOptionAsTextInputTarget() {
        let surface = makeSurface(selectedOptionID: "option-3")

        let state = CodexApprovalInteractionState(surface: surface)

        XCTAssertEqual(state.focusedTarget, .textInput(optionID: "option-3"))
    }

    func testTextInputHeightClampsBetweenTwoAndFourLines() {
        let sizing = CodexApprovalTextInputSizing(lineHeight: 20, verticalPadding: 16)

        XCTAssertEqual(sizing.height(forContentHeight: 0), 56, accuracy: 0.1)
        XCTAssertEqual(sizing.height(forContentHeight: 20), 56, accuracy: 0.1)
        XCTAssertEqual(sizing.height(forContentHeight: 60), 76, accuracy: 0.1)
        XCTAssertEqual(sizing.height(forContentHeight: 120), 96, accuracy: 0.1)
        XCTAssertEqual(sizing.height(forContentHeight: 220), 96, accuracy: 0.1)
    }

    func testTextBoundaryMovesUpOnlyFromFirstLine() {
        XCTAssertTrue(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                text: "first line\nsecond line",
                selectedRange: NSRange(location: 3, length: 0),
                towardStart: true
            )
        )
        XCTAssertFalse(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                text: "first line\nsecond line",
                selectedRange: NSRange(location: 15, length: 0),
                towardStart: true
            )
        )
    }

    func testTextBoundaryMovesDownOnlyFromLastLine() {
        XCTAssertFalse(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                text: "first line\nsecond line",
                selectedRange: NSRange(location: 3, length: 0),
                towardStart: false
            )
        )
        XCTAssertTrue(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                text: "first line\nsecond line",
                selectedRange: NSRange(location: 15, length: 0),
                towardStart: false
            )
        )
    }

    func testTextBoundaryUsesVisualLineRangesWhenProvided() {
        let lineRanges = [
            NSRange(location: 0, length: 10),
            NSRange(location: 10, length: 10),
            NSRange(location: 20, length: 5),
        ]

        XCTAssertTrue(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                selectedRange: NSRange(location: 4, length: 0),
                towardStart: true,
                lineRanges: lineRanges,
                textLength: 25
            )
        )
        XCTAssertFalse(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                selectedRange: NSRange(location: 14, length: 0),
                towardStart: true,
                lineRanges: lineRanges,
                textLength: 25
            )
        )
        XCTAssertFalse(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                selectedRange: NSRange(location: 14, length: 0),
                towardStart: false,
                lineRanges: lineRanges,
                textLength: 25
            )
        )
        XCTAssertTrue(
            CodexApprovalTextBoundary.shouldMoveOutOfTextView(
                selectedRange: NSRange(location: 24, length: 0),
                towardStart: false,
                lineRanges: lineRanges,
                textLength: 25
            )
        )
    }

    @MainActor
    func testTextViewMoveUpOnlyLeavesInputAtFirstLine() {
        let textView = makeTextView(text: "first line\nsecond line")
        let recorder = CodexApprovalBoundaryRecorder()
        textView.boundaryDelegate = recorder

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.moveUp(nil)
        XCTAssertEqual(recorder.moveUpBoundaryCount, 1)

        textView.setSelectedRange(NSRange(location: 15, length: 0))
        textView.moveUp(nil)
        XCTAssertEqual(recorder.moveUpBoundaryCount, 1)
        XCTAssertEqual(recorder.moveWithinTextCount, 1)
    }

    @MainActor
    func testTextViewMoveDownOnlyLeavesInputAtLastLine() {
        let textView = makeTextView(text: "first line\nsecond line")
        let recorder = CodexApprovalBoundaryRecorder()
        textView.boundaryDelegate = recorder

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.moveDown(nil)
        XCTAssertEqual(recorder.moveDownBoundaryCount, 0)
        XCTAssertEqual(recorder.moveWithinTextCount, 1)

        textView.setSelectedRange(NSRange(location: 15, length: 0))
        textView.moveDown(nil)
        XCTAssertEqual(recorder.moveDownBoundaryCount, 1)
    }

    func testDownArrowResolvesToMoveDownInsteadOfSubmit() {
        let event = makeKeyEvent(keyCode: 125, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!))

        XCTAssertEqual(
            CodexApprovalKeyCommand.resolve(
                event: event,
                isEnabled: true,
                focusedTarget: .option(id: "option-1")
            ),
            .moveDown
        )
    }

    func testReturnResolvesToSubmit() {
        let event = makeKeyEvent(keyCode: 36, characters: "\r")

        XCTAssertEqual(
            CodexApprovalKeyCommand.resolve(
                event: event,
                isEnabled: true,
                focusedTarget: .option(id: "option-1")
            ),
            .submit
        )
    }

    func testContainerKeyHandlerIgnoresEventsWhileTextInputIsFocused() {
        let event = makeKeyEvent(keyCode: 125, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!))

        XCTAssertNil(
            CodexApprovalKeyCommand.resolve(
                event: event,
                isEnabled: true,
                focusedTarget: .textInput(optionID: "option-3")
            )
        )
    }

    @MainActor
    func testKeyMonitorBecomesFirstResponderAfterItMovesIntoWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = container

        let monitor = CodexApprovalKeyMonitorView(frame: container.bounds)
        monitor.update(
            isEnabled: true,
            focusedTarget: .option(id: "option-1"),
            onMoveUp: {},
            onMoveDown: {},
            onSubmit: {}
        )

        XCTAssertNil(monitor.window)

        container.addSubview(monitor)

        XCTAssertTrue(window.firstResponder === monitor)
    }

    func testKeyboardSelectionTracksFocusedOption() {
        let surface = makeSurface()
        var state = CodexApprovalInteractionState(surface: surface)

        _ = state.moveDown(surface: surface)

        XCTAssertEqual(state.selectedOptionIDToSync(in: surface), "option-2")

        _ = state.moveDown(surface: surface)

        XCTAssertEqual(state.selectedOptionIDToSync(in: surface), "option-3")
    }

    func testKeyboardSelectionPersistsWhenFocusMovesToButtons() {
        let surface = makeSurface()
        var state = CodexApprovalInteractionState(surface: surface)

        _ = state.moveDown(surface: surface)
        _ = state.moveDown(surface: surface)
        _ = state.moveDown(surface: surface)
        _ = state.moveDown(surface: surface)

        XCTAssertEqual(state.focusedTarget, .submit)
        XCTAssertEqual(state.selectedOptionIDToSync(in: surface), "option-3")
    }

    func testActivatingOptionTreatsClickedOptionAsSelected() {
        let surface = makeSurface()
        var state = CodexApprovalInteractionState(surface: surface)

        let selectedOptionID = state.activateOption("option-2", surface: surface)

        XCTAssertEqual(state.focusedTarget, .option(id: "option-2"))
        XCTAssertEqual(selectedOptionID, "option-2")
        XCTAssertEqual(state.selectedOptionIDToSync(in: surface), "option-2")
    }

    func testSubmitIntentUsesCurrentHighlightedOption() {
        let surface = makeSurface()
        var state = CodexApprovalInteractionState(surface: surface)

        _ = state.focus(.option(id: "option-2"), surface: surface)
        _ = state.focus(.submit, surface: surface)

        XCTAssertEqual(
            state.submitIntent(in: surface),
            .primary(selectedOptionID: "option-2")
        )
    }

    func testTwoOptionSurfaceTreatsTextInputAsStandaloneThirdStep() {
        let surface = makeTwoOptionSurface()
        var state = CodexApprovalInteractionState(surface: surface)

        XCTAssertEqual(state.focusedTarget, .option(id: "option-1"))
        XCTAssertEqual(state.moveDown(surface: surface), .option(id: "option-2"))
        XCTAssertEqual(state.moveDown(surface: surface), .textInput(optionID: nil))
        XCTAssertTrue(state.isTextInputSelected(optionID: nil, in: surface))
        XCTAssertNil(state.selectedOptionIDToSync(in: surface))
        XCTAssertEqual(state.moveDown(surface: surface), .cancel)
    }

    func testTwoOptionSurfaceDoesNotTreatSecondOptionAsFeedbackOption() {
        let surface = makeTwoOptionSurface()

        XCTAssertNil(CodexApprovalInteractionState.feedbackOptionID(for: surface))
    }

    private func makeSurface(selectedOptionID: String = "option-1") -> CodexActionableSurface {
        CodexActionableSurface(
            id: "surface-options",
            summary: "Run command?",
            primaryButtonTitle: "提交 ⏎",
            cancelButtonTitle: "跳过",
            options: [
                CodexSurfaceOption(id: "option-1", index: 1, title: "是", isSelected: selectedOptionID == "option-1"),
                CodexSurfaceOption(id: "option-2", index: 2, title: "是，且对于以后续内容开头的命令不再询问", isSelected: selectedOptionID == "option-2"),
                CodexSurfaceOption(id: "option-3", index: 3, title: "否，请告知 Codex 如何调整", isSelected: selectedOptionID == "option-3"),
            ],
            textInput: CodexSurfaceTextInput(
                title: "告诉 Codex 如何调整",
                text: "",
                isEditable: true,
                attachedOptionID: "option-3"
            )
        )
    }

    private func makeTwoOptionSurface(selectedOptionID: String = "option-1") -> CodexActionableSurface {
        CodexActionableSurface(
            id: "surface-two-options",
            summary: "Run command?",
            primaryButtonTitle: "提交 ⏎",
            cancelButtonTitle: "跳过",
            options: [
                CodexSurfaceOption(id: "option-1", index: 1, title: "是", isSelected: selectedOptionID == "option-1"),
                CodexSurfaceOption(id: "option-2", index: 2, title: "是，且对于以后续内容开头的命令不再询问", isSelected: selectedOptionID == "option-2"),
            ],
            textInput: CodexSurfaceTextInput(
                title: "否，请告知 Codex 如何调整",
                text: "",
                isEditable: true
            )
        )
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            fatalError("failed to create test key event")
        }

        return event
    }

    @MainActor
    private func makeTextView(text: String) -> CodexApprovalNSTextView {
        let textView = CodexApprovalNSTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 80))
        textView.isRichText = false
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 13)
        textView.string = text
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.containerSize = CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        return textView
    }
}
