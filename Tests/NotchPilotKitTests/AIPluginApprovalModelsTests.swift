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
    func testClaudeApprovalSneakNoticeShowsToolNameAndCommand() {
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
        XCTAssertEqual(notice?.text, "Bash: swift build 2>&1 | tail -30")
    }

    @MainActor
    func testClaudeWebFetchSneakNoticeShowsToolNameAndPromptFromHookInput() {
        let runtime = AIAgentRuntime()
        _ = runtime.handle(
            envelope: try! HookEventParser().parse(
                frame: BridgeFrame(
                    host: .claude,
                    requestID: "web-fetch",
                    rawJSON: """
                    {
                      "hook_event_name": "PermissionRequest",
                      "session_id": "claude-session",
                      "tool_name": "WebFetch",
                      "tool_input": {
                        "url": "https://example.com/api",
                        "prompt": "Extract the API endpoints"
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

        XCTAssertEqual(notice?.text, "WebFetch: Extract the API endpoints")
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

    func testCodexApprovalDetailPresentationKeepsNonShellCommandPreviewUnchanged() {
        let presentation = CodexApprovalDetailPresentation(
            surface: CodexActionableSurface(
                id: "surface-1",
                summary: "Run command?",
                commandPreview: "rm -rf '/tmp/demo'",
                primaryButtonTitle: "Submit",
                cancelButtonTitle: "Skip"
            )
        )

        XCTAssertEqual(presentation.commandText, "rm -rf '/tmp/demo'")
    }

    func testCommandDisplayTextKeepsUnquotedLoginShellWrapper() {
        XCTAssertEqual(
            CommandDisplayText.userVisibleCommand("/bin/zsh -lc date"),
            "/bin/zsh -lc date"
        )
    }

    func testCommandDisplayTextKeepsDoubleQuotedLoginShellWrapper() {
        XCTAssertEqual(
            CommandDisplayText.userVisibleCommand(
                #"/bin/zsh -lc "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotchLayoutMetricsTests|NotchWindowTests'""#
            ),
            #"/bin/zsh -lc "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotchLayoutMetricsTests|NotchWindowTests'""#
        )
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

    func testClaudeApprovalOptionPresentationUsesOfficialNumberedOrder() {
        let actions = [
            ApprovalAction(
                id: "claude-deny",
                title: "No",
                style: .outline,
                payload: .claude(.denyOnce)
            ),
            ApprovalAction(
                id: "claude-allow",
                title: "Yes",
                style: .outline,
                payload: .claude(.allowOnce)
            ),
            ApprovalAction(
                id: "claude-allow-persist",
                title: "Yes, and don't ask again for WebFetch(domain:github.com)",
                style: .primary,
                payload: .claude(.allowOnce)
            ),
        ]

        let options = ClaudeApprovalOptionPresentation.options(
            for: actions,
            language: .english
        )

        XCTAssertEqual(options.map(\.indexText), ["1.", "2.", "3."])
        XCTAssertEqual(options.map(\.title), [
            "Yes",
            "Yes, and don't ask again for WebFetch(domain:github.com)",
            "No",
        ])
        XCTAssertEqual(options.map(\.action.id), [
            "claude-allow",
            "claude-allow-persist",
            "claude-deny",
        ])
    }

    func testClaudeApprovalKeyboardFocusMovesThroughOfficialOptions() {
        let options = ClaudeApprovalOptionPresentation.options(
            for: [
                ApprovalAction(
                    id: "claude-deny",
                    title: "No",
                    style: .outline,
                    payload: .claude(.denyOnce)
                ),
                ApprovalAction(
                    id: "claude-allow",
                    title: "Yes",
                    style: .outline,
                    payload: .claude(.allowOnce)
                ),
                ApprovalAction(
                    id: "claude-allow-persist",
                    title: "Yes, and don't ask again for WebFetch(domain:github.com)",
                    style: .primary,
                    payload: .claude(.allowOnce)
                ),
            ],
            language: .english
        )
        var state = ClaudeApprovalInteractionState(options: options)

        XCTAssertEqual(state.focusedActionID, "claude-allow")
        XCTAssertEqual(state.moveDown(options: options), "claude-allow-persist")
        XCTAssertEqual(state.moveDown(options: options), "claude-deny")
        XCTAssertEqual(state.moveDown(options: options), "claude-deny")
        XCTAssertEqual(state.moveUp(options: options), "claude-allow-persist")
        XCTAssertEqual(state.moveUp(options: options), "claude-allow")
        XCTAssertEqual(state.focusedAction(in: options)?.id, "claude-allow")
    }
}
