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
