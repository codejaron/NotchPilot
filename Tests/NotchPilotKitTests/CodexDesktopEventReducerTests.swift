import XCTest
@testable import NotchPilotKit

final class CodexDesktopEventReducerTests: XCTestCase {
    func testThreadStreamSnapshotCreatesSessionFromConversationState() throws {
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
                                    "last": .object([
                                        "inputTokens": .integer(123),
                                        "outputTokens": .integer(45),
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

        guard case let .sessionUpsert(session)? = outputs.last else {
            return XCTFail("expected session output")
        }

        XCTAssertEqual(session.id, "conv-1")
        XCTAssertEqual(session.host, .codex)
        XCTAssertEqual(session.sessionTitle, "Implement desktop IPC")
        XCTAssertEqual(session.activityLabel, "Working")
        XCTAssertEqual(session.inputTokenCount, 123)
        XCTAssertEqual(session.outputTokenCount, 45)
    }

    func testThreadStreamPatchesUpdateExistingSession() throws {
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
                                        "last": .object([
                                            "inputTokens": .integer(999),
                                            "outputTokens": .integer(111),
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

        guard case let .sessionUpsert(session)? = outputs.last else {
            return XCTFail("expected updated session output")
        }

        XCTAssertEqual(session.id, "conv-2")
        XCTAssertEqual(session.sessionTitle, "Updated Title")
        XCTAssertEqual(session.activityLabel, "Working")
        XCTAssertEqual(session.inputTokenCount, 999)
        XCTAssertEqual(session.outputTokenCount, 111)
    }

    func testCommandApprovalUsesConversationStateItem() throws {
        var reducer = CodexDesktopEventReducer()

        _ = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("thr-1"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("thr-1"),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-1"),
                                        "status": .string("inProgress"),
                                        "items": .array([
                                            .object([
                                                "id": .string("item-1"),
                                                "type": .string("commandExecution"),
                                                "command": .array([.string("npm"), .string("test")]),
                                                "cwd": .string("/tmp/project"),
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
            frame: .request(
                CodexDesktopIPCRequestFrame(
                    requestID: "req-1",
                    method: "item/commandExecution/requestApproval",
                    params: [
                        "threadId": .string("thr-1"),
                        "turnId": .string("turn-1"),
                        "itemId": .string("item-1"),
                        "reason": .string("Needs approval"),
                        "availableDecisions": .array([
                            .string("accept"),
                            .string("acceptForSession"),
                            .string("decline"),
                            .string("cancel"),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .approvalRequested(approval)? = outputs.last else {
            return XCTFail("expected approval output")
        }

        XCTAssertEqual(approval.requestID, "req-1")
        XCTAssertEqual(approval.sessionID, "thr-1")
        XCTAssertEqual(approval.approvalKind, .commandExecution)
        XCTAssertEqual(approval.payload.command, "npm test")
        XCTAssertEqual(approval.cwd, "/tmp/project")
        XCTAssertEqual(approval.reason, "Needs approval")
        XCTAssertEqual(
            approval.availableActions.map(\.title),
            ["Allow", "Allow for Session", "Decline", "Cancel"]
        )
    }

    func testFileChangeApprovalBuildsPreviewFromConversationState() throws {
        var reducer = CodexDesktopEventReducer()

        _ = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("thr-2"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("thr-2"),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-2"),
                                        "status": .string("inProgress"),
                                        "items": .array([
                                            .object([
                                                "id": .string("item-2"),
                                                "type": .string("fileChange"),
                                                "changes": .array([
                                                    .object([
                                                        "path": .string("/tmp/demo.txt"),
                                                        "oldText": .string("before"),
                                                        "newText": .string("after"),
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

        let outputs = try reducer.consume(
            frame: .request(
                CodexDesktopIPCRequestFrame(
                    requestID: "req-2",
                    method: "item/fileChange/requestApproval",
                    params: [
                        "threadId": .string("thr-2"),
                        "turnId": .string("turn-2"),
                        "itemId": .string("item-2"),
                        "reason": .string("Review patch"),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .approvalRequested(approval)? = outputs.last else {
            return XCTFail("expected file approval")
        }

        XCTAssertEqual(approval.approvalKind, .fileChange)
        XCTAssertEqual(approval.payload.filePath, "/tmp/demo.txt")
        XCTAssertEqual(approval.payload.originalContent, "before")
        XCTAssertEqual(approval.payload.diffContent, "after")
        XCTAssertEqual(
            approval.availableActions.map(\.title),
            ["Allow", "Allow for Session", "Decline", "Cancel"]
        )
    }

    func testResolvedRequestRemovesApprovalByRequestID() throws {
        var reducer = CodexDesktopEventReducer()

        let outputs = try reducer.consume(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "serverRequest/resolved",
                    params: [
                        "threadId": .string("thr-3"),
                        "requestId": .string("req-3"),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        guard case let .approvalResolved(requestID)? = outputs.last else {
            return XCTFail("expected resolved request output")
        }

        XCTAssertEqual(requestID, "req-3")
    }

}
