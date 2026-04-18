import XCTest
@testable import NotchPilotKit

final class CodexDesktopEventReducerTests: XCTestCase {
    func testThreadStreamSnapshotCreatesThreadContextFromConversationState() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-1"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-1"),
                                "title": .string("Implement desktop IPC"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("notLoaded"),
                                ]),
                                "latestTokenUsageInfo": .object([
                                    "total": .object([
                                        "inputTokens": .integer(4567),
                                        "outputTokens": .integer(890),
                                    ]),
                                ]),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-1"),
                                        "status": .string("inProgress"),
                                        "items": .array([]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.threadID, "conv-1")
        XCTAssertEqual(context.title, "Implement desktop IPC")
        XCTAssertEqual(context.activityLabel, "Working")
        XCTAssertEqual(context.phase, .working)
        XCTAssertEqual(context.inputTokenCount, 4567)
        XCTAssertEqual(context.outputTokenCount, 890)
        XCTAssertEqual(context.launchContext?.codexClientID, "desktop-client")
        XCTAssertFalse(marksActivity)
    }

    func testThreadStreamPatchesUpdateExistingThreadContext() throws {
        var reducer = CodexDesktopEventReducer()

        _ = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-2"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-2"),
                                "title": .string("Initial Title"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("notLoaded"),
                                ]),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-1"),
                                        "status": .string("completed"),
                                        "items": .array([]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-2"),
                        "change": .object([
                            "type": .string("patches"),
                            "patches": .array([
                                .object([
                                    "op": .string("replace"),
                                    "path": .array([.string("title")]),
                                    "value": .string("Updated Title"),
                                ]),
                                .object([
                                    "op": .string("replace"),
                                    "path": .array([.string("turns"), .integer(0), .string("status")]),
                                    "value": .string("inProgress"),
                                ]),
                                .object([
                                    "op": .string("replace"),
                                    "path": .array([.string("latestTokenUsageInfo")]),
                                    "value": .object([
                                        "total": .object([
                                            "inputTokens": .integer(7000),
                                            "outputTokens": .integer(1500),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected updated thread context output")
        }

        XCTAssertEqual(context.threadID, "conv-2")
        XCTAssertEqual(context.title, "Updated Title")
        XCTAssertEqual(context.activityLabel, "Working")
        XCTAssertEqual(context.phase, .working)
        XCTAssertEqual(context.inputTokenCount, 7000)
        XCTAssertEqual(context.outputTokenCount, 1500)
        XCTAssertTrue(marksActivity)
    }

    func testLatestTurnInProgressReflectsLatestTurnStatus() throws {
        var reducer = CodexDesktopEventReducer()

        _ = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-turn-state"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-turn-state"),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-1"),
                                        "status": .string("inProgress"),
                                        "items": .array([]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(reducer.isLatestTurnInProgress(for: "conv-turn-state"), true)

        _ = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-turn-state"),
                        "change": .object([
                            "type": .string("patches"),
                            "patches": .array([
                                .object([
                                    "op": .string("replace"),
                                    "path": .array([.string("turns"), .integer(0), .string("status")]),
                                    "value": .string("completed"),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(reducer.isLatestTurnInProgress(for: "conv-turn-state"), false)
        XCTAssertNil(reducer.isLatestTurnInProgress(for: "missing-conversation"))
    }

    func testThreadMetadataUpdateRequestSetsThreadTitleWithoutMarkingActivity() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .request(
                CodexDesktopIPCRequestFrame(
                    requestID: "req-thread-title",
                    method: "thread/metadata/update",
                    params: [
                        "conversationId": .string("conv-meta"),
                        "metadata": .object([
                            "title": .string("Real Thread Title"),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.threadID, "conv-meta")
        XCTAssertEqual(context.title, "Real Thread Title")
        XCTAssertFalse(marksActivity)
    }

    func testThreadMetadataUpdateRequestUsesMetadataNameWhenItIsReadable() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .request(
                CodexDesktopIPCRequestFrame(
                    requestID: "req-thread-name",
                    method: "thread/metadata/update",
                    params: [
                        "conversationId": .string("conv-readable-name"),
                        "metadata": .object([
                            "name": .string("Fix Approval Mirror UI"),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.threadID, "conv-readable-name")
        XCTAssertEqual(context.title, "Fix Approval Mirror UI")
        XCTAssertFalse(marksActivity)
    }

    func testThreadStreamSnapshotEmitsActionableApprovalRequestFromConversationRequests() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-approval"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-approval"),
                                "title": .string("Needs approval"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(2),
                                        "params": .object([
                                            "threadId": .string("conv-approval"),
                                            "reason": .string("Do you want to run this?"),
                                            "command": .string("/bin/zsh -lc date"),
                                            "cwd": .string("/Users/jaron/data/project/NotchPilot"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                                .string("cancel"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .approvalRequestChanged(request)? = outputs.last else {
            return XCTFail("expected approval request output")
        }

        XCTAssertEqual(request?.requestID, "2")
        XCTAssertEqual(request?.rawRequestID, .integer(2))
        XCTAssertEqual(request?.method, "item/commandExecution/requestApproval")
        XCTAssertEqual(request?.params["threadId"]?.stringValue, "conv-approval")
        XCTAssertEqual(request?.params["command"]?.stringValue, "/bin/zsh -lc date")
        XCTAssertEqual(request?.sourceClientID, "desktop-client")
    }

    func testThreadStreamPatchesClearActionableApprovalRequestWhenRequestsBecomeEmpty() throws {
        var reducer = CodexDesktopEventReducer()

        _ = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-clear-approval"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-clear-approval"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(5),
                                        "params": .object([
                                            "threadId": .string("conv-clear-approval"),
                                            "reason": .string("Approve?"),
                                            "command": .string("date"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-clear-approval"),
                        "change": .object([
                            "type": .string("patches"),
                            "patches": .array([
                                .object([
                                    "op": .string("replace"),
                                    "path": .array([.string("requests")]),
                                    "value": .array([]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .approvalRequestChanged(request)? = outputs.last else {
            return XCTFail("expected approval request output")
        }

        XCTAssertNil(request)
    }

    func testThreadStreamSnapshotPrefersUserInputRequestOverApprovalRequest() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-prefer-user-input"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-prefer-user-input"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(20),
                                        "params": .object([
                                            "threadId": .string("conv-prefer-user-input"),
                                            "turnId": .string("turn-prefer-user-input"),
                                            "command": .string("rm -rf '/tmp/demo'"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                                .string("decline"),
                                            ]),
                                        ]),
                                    ]),
                                    .object([
                                        "method": .string("item/tool/requestUserInput"),
                                        "id": .integer(21),
                                        "params": .object([
                                            "threadId": .string("conv-prefer-user-input"),
                                            "turnId": .string("turn-prefer-user-input"),
                                            "itemId": .string("item-prefer-user-input"),
                                            "questions": .array([
                                                .object([
                                                    "id": .string("question-prefer-user-input"),
                                                    "question": .string("How should Codex adjust?"),
                                                    "isOther": .bool(true),
                                                    "options": .array([
                                                        .object([
                                                            "label": .string("Proceed as-is"),
                                                            "description": .string("Keep going."),
                                                        ]),
                                                    ]),
                                                ]),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .approvalRequestChanged(request)? = outputs.last else {
            return XCTFail("expected actionable request output")
        }

        XCTAssertEqual(request?.requestID, "21")
        XCTAssertEqual(request?.rawRequestID, .integer(21))
        XCTAssertEqual(request?.method, "item/tool/requestUserInput")
        XCTAssertEqual(request?.params["threadId"]?.stringValue, "conv-prefer-user-input")
    }

    func testThreadStreamPatchesEmitApprovalRequestWhenArrayIndexPathUsesStringIndex() throws {
        var reducer = CodexDesktopEventReducer()

        _ = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-string-index-approval"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-string-index-approval"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "requests": .array([]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-string-index-approval"),
                        "change": .object([
                            "type": .string("patches"),
                            "patches": .array([
                                .object([
                                    "op": .string("add"),
                                    "path": .array([.string("requests"), .string("0")]),
                                    "value": .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .string("req-string-index"),
                                        "params": .object([
                                            "threadId": .string("conv-string-index-approval"),
                                            "reason": .string("Approve string index patch?"),
                                            "command": .string("date"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard let approvalOutput = outputs.first(where: {
            if case .approvalRequestChanged = $0 {
                return true
            }
            return false
        }) else {
            return XCTFail("expected approval request output")
        }

        guard case let .approvalRequestChanged(request) = approvalOutput else {
            return XCTFail("expected approval request output")
        }

        XCTAssertEqual(request?.requestID, "req-string-index")
        XCTAssertEqual(request?.method, "item/commandExecution/requestApproval")
    }

    func testThreadStreamPatchesCanCreateApprovalRequestWithoutPriorSnapshot() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-patch-first-approval"),
                        "change": .object([
                            "type": .string("patches"),
                            "patches": .array([
                                .object([
                                    "op": .string("replace"),
                                    "path": .array([.string("requests")]),
                                    "value": .array([
                                        .object([
                                            "method": .string("item/commandExecution/requestApproval"),
                                            "id": .string("req-patch-first"),
                                            "params": .object([
                                                "threadId": .string("conv-patch-first-approval"),
                                                "reason": .string("Approve without snapshot?"),
                                                "command": .string("date"),
                                                "availableDecisions": .array([
                                                    .string("accept"),
                                                ]),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard let approvalOutput = outputs.first(where: {
            if case .approvalRequestChanged = $0 {
                return true
            }
            return false
        }) else {
            return XCTFail("expected approval request output")
        }

        guard case let .approvalRequestChanged(request) = approvalOutput else {
            return XCTFail("expected approval request output")
        }

        XCTAssertEqual(request?.requestID, "req-patch-first")
        XCTAssertEqual(request?.method, "item/commandExecution/requestApproval")
    }

    func testThreadStreamPatchesEmitApprovalRequestAfterEmptyRequestsPatchForLiveSequence() throws {
        var reducer = CodexDesktopEventReducer()

        let clearOutputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-live-sequence"),
                        "change": .object([
                            "type": .string("patches"),
                            "patches": .array([
                                .object([
                                    "op": .string("replace"),
                                    "path": .array([.string("requests")]),
                                    "value": .array([]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertFalse(clearOutputs.contains(where: {
            if case .approvalRequestChanged = $0 {
                return true
            }
            return false
        }))

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-live-sequence"),
                        "change": .object([
                            "type": .string("patches"),
                            "patches": .array([
                                .object([
                                    "op": .string("add"),
                                    "path": .array([.string("requests"), .integer(0)]),
                                    "value": .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(66),
                                        "params": .object([
                                            "threadId": .string("conv-live-sequence"),
                                            "turnId": .string("turn-live"),
                                            "itemId": .string("item-live"),
                                            "reason": .string("Do you want to approve deleting the temporary directory I just created for this test?"),
                                            "command": .string("/bin/zsh -lc \"rm -rf '/tmp/live-sequence'\""),
                                            "cwd": .string("/tmp"),
                                            "commandActions": .array([
                                                .object([
                                                    "type": .string("unknown"),
                                                    "command": .string("rm -rf '/tmp/live-sequence'"),
                                                ]),
                                            ]),
                                            "proposedExecpolicyAmendment": .array([
                                                .string("rm"),
                                                .string("-rf"),
                                                .string("/tmp/live-sequence"),
                                            ]),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                                .object([
                                                    "acceptWithExecpolicyAmendment": .object([
                                                        "execpolicy_amendment": .array([
                                                            .string("rm"),
                                                            .string("-rf"),
                                                            .string("/tmp/live-sequence"),
                                                        ]),
                                                    ]),
                                                ]),
                                                .string("cancel"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard let approvalOutput = outputs.first(where: {
            if case .approvalRequestChanged = $0 {
                return true
            }
            return false
        }) else {
            return XCTFail("expected approval request output")
        }

        guard case let .approvalRequestChanged(request) = approvalOutput else {
            return XCTFail("expected approval request output")
        }

        XCTAssertEqual(request?.requestID, "66")
        XCTAssertEqual(request?.method, "item/commandExecution/requestApproval")
        XCTAssertEqual(request?.params["threadId"]?.stringValue, "conv-live-sequence")
    }

    func testThreadStreamUsesExplicitPlanModeBeforeTurnStatus() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-plan"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-plan"),
                                "title": .string("Write a plan"),
                                "mode": .string("plan"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("running"),
                                ]),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-plan"),
                                        "status": .string("inProgress"),
                                        "items": .array([]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.phase, .plan)
        XCTAssertEqual(context.activityLabel, "Plan")
        XCTAssertFalse(marksActivity)
    }

    func testThreadStreamFallsBackToRuntimeStatusWhenNoTurnStatusExists() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-runtime"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-runtime"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.phase, .connected)
        XCTAssertEqual(context.activityLabel, "Connected")
        XCTAssertFalse(marksActivity)
    }

    func testThreadStreamUsesThreadMetadataTitleWhenTopLevelTitleIsMissing() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-thread-name"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-thread-name"),
                                "thread": .object([
                                    "title": .string("Named From Metadata"),
                                ]),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.threadID, "conv-thread-name")
        XCTAssertEqual(context.title, "Named From Metadata")
        XCTAssertFalse(marksActivity)
    }

    func testThreadStreamIgnoresGenericNameFieldWhenTitleIsMissing() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-generic-name"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-generic-name"),
                                "name": .string("019d6aff-09ea-70c0-8cb4-efbd0565ce68"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.threadID, "conv-generic-name")
        XCTAssertNil(context.title)
        XCTAssertFalse(marksActivity)
    }

    func testThreadStreamUsesReadableNameFieldWhenTitleIsMissing() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-readable-name"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-readable-name"),
                                "metadata": .object([
                                    "name": .string("Readable IPC Thread Name"),
                                ]),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertEqual(context.threadID, "conv-readable-name")
        XCTAssertEqual(context.title, "Readable IPC Thread Name")
        XCTAssertFalse(marksActivity)
    }

    func testThreadStreamDoesNotUseLatestUserPromptAsFallbackTitle() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-no-title"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-no-title"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-1"),
                                        "status": .string("completed"),
                                        "items": .array([
                                            .object([
                                                "type": .string("userMessage"),
                                                "content": .array([
                                                    .object([
                                                        "text": .string("请实现 Codex 审批旁路接入"),
                                                    ]),
                                                ]),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .threadContextUpsert(context, marksActivity: marksActivity)? = outputs.last else {
            return XCTFail("expected thread context output")
        }

        XCTAssertNil(context.title)
        XCTAssertFalse(marksActivity)
    }
}
