import XCTest
@testable import NotchPilotKit

final class AIPluginApprovalModelsTests: XCTestCase {
    func testCodexApprovalSneakNoticePrefersSurfaceSummaryOverCommandPreview() {
        let notice = AIPluginApprovalSneakNotice(
            pendingApprovals: [],
            codexSurface: CodexActionableSurface(
                id: "surface-1",
                summary: "Run command?",
                commandPreview: "/bin/zsh -lc \"echo test\"",
                primaryButtonTitle: "Submit",
                cancelButtonTitle: "Skip"
            )
        )

        XCTAssertEqual(notice?.count, 1)
        XCTAssertEqual(notice?.text, "Run command?")
    }

    @MainActor
    func testClaudeApprovalSneakNoticePrefersDescriptionOverCommand() {
        let runtime = AIAgentRuntime()
        _ = runtime.handle(
            envelope: try! HookEventParser().parse(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "claude-approval-description",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "claude-session-description",
                      "tool_name": "Bash",
                      "tool_input": {
                        "command": "swift build 2>&1 | tail -30",
                        "description": "Build the Swift package"
                      }
                    }
                    """
                )
            )
        )

        let notice = AIPluginApprovalSneakNotice(
            pendingApprovals: runtime.pendingApprovals,
            codexSurface: nil
        )

        XCTAssertEqual(notice?.count, 1)
        XCTAssertEqual(notice?.text, "Build the Swift package")
    }

    func testCodexApprovalDetailPresentationShowsSummaryAboveCommandPreview() {
        let presentation = CodexApprovalDetailPresentation(
            surface: CodexActionableSurface(
                id: "surface-1",
                summary: "Do you want me to run the broader notch tests?",
                commandPreview: "/bin/zsh -lc 'swift test --filter \"NotchLayoutMetricsTests\"'",
                primaryButtonTitle: "Submit",
                cancelButtonTitle: "Skip"
            )
        )

        XCTAssertEqual(presentation.summaryText, "Do you want me to run the broader notch tests?")
        XCTAssertEqual(presentation.commandText, "/bin/zsh -lc 'swift test --filter \"NotchLayoutMetricsTests\"'")
    }

    func testStandaloneCodexTextInputPresentationPlacesIndexInsideField() {
        let presentation = CodexApprovalTextInputPresentation.standalone(
            textInput: CodexSurfaceTextInput(
                title: nil,
                text: "",
                isEditable: true
            ),
            index: 3
        )

        XCTAssertEqual(presentation.indexText, "3.")
        XCTAssertEqual(presentation.indexPlacement, .insideFieldLeading)
    }

    func testFeedbackCodexTextInputPresentationPlacesOptionIndexInsideField() {
        let presentation = CodexApprovalTextInputPresentation.feedback(
            textInput: CodexSurfaceTextInput(
                title: "Explain what to change",
                text: "",
                isEditable: true,
                attachedOptionID: "feedback"
            ),
            option: CodexSurfaceOption(
                id: "feedback",
                index: 3,
                title: "No, tell Codex how to adjust",
                isSelected: true
            )
        )

        XCTAssertEqual(presentation.indexText, "3.")
        XCTAssertEqual(presentation.indexPlacement, .insideFieldLeading)
        XCTAssertEqual(presentation.placeholder, "Explain what to change")
    }
}
