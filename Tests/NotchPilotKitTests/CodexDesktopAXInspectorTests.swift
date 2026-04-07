import ApplicationServices
import XCTest
@testable import NotchPilotKit

final class CodexDesktopAXInspectorTests: XCTestCase {
    func testInspectorIgnoresSingleButtonCardInsideWebArea() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "request-card",
                                        value: "Run command?",
                                        children: [
                                            buttonNode(id: "button-submit", title: "Submit"),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        XCTAssertNil(inspector.inspect(snapshot: snapshot))
    }

    func testInspectorUsesTrailingButtonAsPrimaryForStructuredTwoButtonCard() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "request-card",
                                        value: "Run command?",
                                        children: [
                                            buttonNode(id: "button-skip", title: "Skip"),
                                            buttonNode(id: "button-submit", title: "Submit"),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        let inspection = inspector.inspect(snapshot: snapshot)

        XCTAssertEqual(inspection?.surface.primaryButtonTitle, "Submit")
        XCTAssertEqual(inspection?.surface.cancelButtonTitle, "Skip")
        XCTAssertEqual(inspection?.primaryActionNodeID, "button-submit")
        XCTAssertEqual(inspection?.cancelActionNodeID, "button-skip")
    }

    func testInspectorFindsInlineRequestCardInsideWebArea() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            groupNode(
                                id: "toolbar",
                                children: [
                                    buttonNode(id: "button-new-task", title: "New Task"),
                                ]
                            ),
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "conversation",
                                        children: [
                                            groupNode(
                                                id: "pending-request",
                                                value: "Do you want to run this command?",
                                                children: [
                                                    buttonNode(id: "button-no", title: "No"),
                                                    buttonNode(id: "button-yes", title: "Yes"),
                                                ]
                                            ),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        let inspection = inspector.inspect(snapshot: snapshot)

        XCTAssertEqual(inspection?.surface.summary, "Do you want to run this command?")
        XCTAssertEqual(inspection?.surface.primaryButtonTitle, "Yes")
        XCTAssertEqual(inspection?.surface.cancelButtonTitle, "No")
        XCTAssertEqual(inspection?.primaryActionNodeID, "button-yes")
        XCTAssertEqual(inspection?.cancelActionNodeID, "button-no")
    }

    func testInspectorUsesContainerValueBeforeStaticTextForRequestSummary() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "pending-request",
                                        value: "Do you want to approve deleting the temporary test file with rm -rf?\n否，请告知 Codex 如何调整",
                                        children: [
                                            staticTextNode(id: "text-1", value: "无关说明，不该覆盖容器 value"),
                                            buttonNode(id: "button-skip", title: "跳过"),
                                            buttonNode(id: "button-submit", title: "提交"),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        let inspection = inspector.inspect(snapshot: snapshot)

        XCTAssertEqual(
            inspection?.surface.summary,
            "Do you want to approve deleting the temporary test file with rm -rf?\n否，请告知 Codex 如何调整"
        )
        XCTAssertEqual(inspection?.surface.primaryButtonTitle, "提交")
        XCTAssertEqual(inspection?.surface.cancelButtonTitle, "跳过")
    }

    func testInspectorIgnoresNavigationLandmarkCandidateEvenWhenShapeLooksValid() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "sidebar",
                                        subrole: "AXLandmarkNavigation",
                                        children: [
                                            groupNode(
                                                id: "sidebar-card",
                                                value: "Run command?",
                                                children: [
                                                    buttonNode(id: "button-skip", title: "Skip"),
                                                    buttonNode(id: "button-submit", title: "Submit"),
                                                ]
                                            ),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        XCTAssertNil(inspector.inspect(snapshot: snapshot))
    }

    func testInspectorDoesNotTreatGenericWebControlsAsApprovalSurface() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "content",
                                        children: [
                                            staticTextNode(id: "text-1", value: "Recent tasks"),
                                            buttonNode(id: "button-open", title: "Open"),
                                            buttonNode(id: "button-share", title: "Share"),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        XCTAssertNil(inspector.inspect(snapshot: snapshot))
    }

    func testInspectorFindsRealCodexApprovalPromptUsingContainerValueAndTwoButtonStructure() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "conversation",
                                        children: [
                                            groupNode(
                                                id: "pending-request",
                                                value: "Do you want to approve deleting the temporary test file with rm -rf?\n否，请告知 Codex 如何调整",
                                                children: [
                                                    buttonNode(id: "button-skip", title: "跳过"),
                                                    buttonNode(id: "button-submit", title: "提交"),
                                                ]
                                            ),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        let inspection = inspector.inspect(snapshot: snapshot)

        XCTAssertEqual(
            inspection?.surface.summary,
            "Do you want to approve deleting the temporary test file with rm -rf?\n否，请告知 Codex 如何调整"
        )
        XCTAssertEqual(inspection?.surface.primaryButtonTitle, "提交")
        XCTAssertEqual(inspection?.surface.cancelButtonTitle, "跳过")
        XCTAssertEqual(inspection?.primaryActionNodeID, "button-submit")
        XCTAssertEqual(inspection?.cancelActionNodeID, "button-skip")
    }

    func testInspectorAcceptsLiveCodexApprovalCardUsingDescriptionRadioGroupAndTextArea() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "approval-card",
                                        description: "Do you want to approve deleting the temporary test file with rm -rf? rm -rf '/Users/jaron/Documents/New project/codex-temp-delete-me.txt' 3。 否，请告知 Codex 如何调整 否，请告知 Codex 如何调整 跳过 提交 ⏎",
                                        children: [
                                            groupNode(id: "lead-1", children: []),
                                            groupNode(id: "lead-2", children: []),
                                            radioGroupNode(
                                                id: "radio-group",
                                                children: [
                                                    radioButtonNode(id: "radio-1", title: "是"),
                                                    radioButtonNode(id: "radio-2", title: "是，且对于以后续内容开头的命令不再询问"),
                                                    radioButtonNode(id: "radio-3", title: "否，请告知 Codex 如何调整", selected: true),
                                                ]
                                            ),
                                            staticTextNode(id: "text-1", value: "Do you want to approve deleting the temporary test file with rm -rf?"),
                                            staticTextNode(id: "text-2", value: "否，请告知 Codex 如何调整"),
                                            textAreaNode(id: "text-area", value: "请改成 move to trash", isValueSettable: true),
                                            buttonNode(id: "button-skip", title: "跳过"),
                                            buttonNode(id: "button-submit", title: "提交 ⏎"),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        let inspection = inspector.inspect(snapshot: snapshot)

        XCTAssertEqual(inspection?.surface.summary, "Do you want to approve deleting the temporary test file with rm -rf? rm -rf '/Users/jaron/Documents/New project/codex-temp-delete-me.txt' 3。 否，请告知 Codex 如何调整 否，请告知 Codex 如何调整 跳过 提交 ⏎")
        XCTAssertEqual(inspection?.surface.primaryButtonTitle, "提交 ⏎")
        XCTAssertEqual(inspection?.surface.cancelButtonTitle, "跳过")
        XCTAssertEqual(
            inspection?.surface.options,
            [
                CodexSurfaceOption(id: "radio-1", index: 1, title: "是", isSelected: false),
                CodexSurfaceOption(id: "radio-2", index: 2, title: "是，且对于以后续内容开头的命令不再询问", isSelected: false),
                CodexSurfaceOption(id: "radio-3", index: 3, title: "否，请告知 Codex 如何调整", isSelected: true),
            ]
        )
        XCTAssertEqual(
            inspection?.surface.textInput,
            CodexSurfaceTextInput(
                title: "否，请告知 Codex 如何调整",
                text: "请改成 move to trash",
                isEditable: true
            )
        )
        XCTAssertEqual(inspection?.primaryActionNodeID, "button-submit")
        XCTAssertEqual(inspection?.cancelActionNodeID, "button-skip")
    }

    func testInspectorIgnoresMessageCardWithoutContainerValueEvenWhenBodyMentionsApprovals() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "conversation",
                                        children: [
                                            groupNode(
                                                id: "message-card",
                                                children: [
                                                    staticTextNode(
                                                        id: "text-1",
                                                        value: "现在会合并 Claude 审批、Codex thread context、Codex AX surface"
                                                    ),
                                                    staticTextNode(
                                                        id: "text-2",
                                                        value: "展开态对 Codex 只显示真实的 primary/cancel"
                                                    ),
                                                    buttonNode(id: "button-file", title: "AIHooksSettingsTab.swift"),
                                                ]
                                            ),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        XCTAssertNil(inspector.inspect(snapshot: snapshot))
    }

    func testInspectorIgnoresGenericTwoButtonMessageCardWithOnlyDescendantStaticText() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "conversation",
                                        children: [
                                            groupNode(
                                                id: "message-card",
                                                children: [
                                                    staticTextNode(
                                                        id: "text-1",
                                                        value: "继续保留对 thread-stream-state-changed 的审批上下文解析"
                                                    ),
                                                    staticTextNode(
                                                        id: "text-2",
                                                        value: "Codex 改成 AX 后应收敛为真实按钮"
                                                    ),
                                                    buttonNode(id: "button-open", title: "Open file"),
                                                    buttonNode(id: "button-copy", title: "Copy"),
                                                ]
                                            ),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        XCTAssertNil(inspector.inspect(snapshot: snapshot))
    }

    func testInspectorIgnoresCardWithNestedInteractiveControls() {
        let inspector = CodexDesktopAXInspector()
        let snapshot = CodexDesktopAXSnapshot(
            pid: 42,
            windows: [
                CodexDesktopAXWindowSnapshot(
                    id: "window-1",
                    isFocused: true,
                    root: windowNode(
                        id: "window-1",
                        children: [
                            webAreaNode(
                                id: "web-area-1",
                                children: [
                                    groupNode(
                                        id: "request-card",
                                        value: "Run command?",
                                        children: [
                                            buttonNode(id: "button-skip", title: "Skip"),
                                            buttonNode(id: "button-submit", title: "Submit"),
                                            textFieldNode(id: "field-1"),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )

        XCTAssertNil(inspector.inspect(snapshot: snapshot))
    }

    private func windowNode(id: String, children: [CodexDesktopAXNode]) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: kAXWindowRole as String,
            subrole: nil,
            title: nil,
            description: nil,
            value: nil,
            selected: nil,
            isValueSettable: nil,
            isEnabled: true,
            children: children
        )
    }

    private func webAreaNode(id: String, children: [CodexDesktopAXNode]) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: "AXWebArea",
            subrole: nil,
            title: nil,
            description: nil,
            value: nil,
            selected: nil,
            isValueSettable: nil,
            isEnabled: true,
            children: children
        )
    }

    private func groupNode(
        id: String,
        subrole: String? = nil,
        description: String? = nil,
        value: String? = nil,
        children: [CodexDesktopAXNode]
    ) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: kAXGroupRole as String,
            subrole: subrole,
            title: nil,
            description: description,
            value: value,
            selected: nil,
            isValueSettable: nil,
            isEnabled: true,
            children: children
        )
    }

    private func buttonNode(id: String, title: String) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: kAXButtonRole as String,
            subrole: nil,
            title: title,
            description: nil,
            value: nil,
            selected: nil,
            isValueSettable: nil,
            isEnabled: true,
            children: []
        )
    }

    private func staticTextNode(id: String, value: String) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: kAXStaticTextRole as String,
            subrole: nil,
            title: nil,
            description: nil,
            value: value,
            selected: nil,
            isValueSettable: nil,
            isEnabled: true,
            children: []
        )
    }

    private func textFieldNode(id: String) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: "AXTextField",
            subrole: nil,
            title: nil,
            description: nil,
            value: nil,
            selected: nil,
            isValueSettable: nil,
            isEnabled: true,
            children: []
        )
    }

    private func textAreaNode(
        id: String,
        value: String? = nil,
        isValueSettable: Bool? = nil
    ) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: "AXTextArea",
            subrole: nil,
            title: nil,
            description: nil,
            value: value,
            selected: nil,
            isValueSettable: isValueSettable,
            isEnabled: true,
            children: []
        )
    }

    private func radioGroupNode(id: String, children: [CodexDesktopAXNode]) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: "AXRadioGroup",
            subrole: nil,
            title: nil,
            description: nil,
            value: nil,
            selected: nil,
            isValueSettable: nil,
            isEnabled: true,
            children: children
        )
    }

    private func radioButtonNode(
        id: String,
        title: String,
        selected: Bool = false
    ) -> CodexDesktopAXNode {
        CodexDesktopAXNode(
            id: id,
            role: "AXRadioButton",
            subrole: nil,
            title: title,
            description: nil,
            value: nil,
            selected: selected,
            isValueSettable: nil,
            isEnabled: true,
            children: []
        )
    }
}
