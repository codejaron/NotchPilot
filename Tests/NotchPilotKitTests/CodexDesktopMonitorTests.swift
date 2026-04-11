import Darwin
import Foundation
import XCTest
@testable import NotchPilotKit

final class CodexDesktopMonitorTests: XCTestCase {
    func testCanHandleDiscoveryRequestRecognizesSupportedApprovalRequests() {
        let approvalRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1",
            method: "item/commandExecution/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let fileChangeRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1b",
            method: "item/fileChange/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let legacyExecRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1legacy",
            method: "execCommandApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let legacyPatchRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1patch",
            method: "applyPatchApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let userInputRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1input",
            method: "item/tool/requestUserInput",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let permissionsRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1c",
            method: "item/permissions/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let nonApprovalRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-2",
            method: "ide-context",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )

        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(approvalRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(fileChangeRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(legacyExecRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(legacyPatchRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(userInputRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(permissionsRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nonApprovalRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nil))
    }

    func testPerformingLiveCommandApprovalSendsThreadFollowerDecisionRequest() throws {
        let server = try TestCodexIPCServer()
        defer { server.stop() }

        let monitor = CodexDesktopMonitor(
            detector: CodexDesktopAppDetector(
                fileManager: .default,
                homeDirectoryURL: server.installedAppHomeDirectoryURL
            ),
            discovery: CodexDesktopIPCDiscovery(directoryURL: server.socketDirectoryURL),
            requestTimeout: 1
        )
        let surfaceSignal = DispatchSemaphore(value: 0)
        monitor.onSurfaceChanged = { surface in
            guard surface?.id == "codex-ipc-66" else { return }
            surfaceSignal.signal()
        }

        monitor.start()
        defer { monitor.stop() }

        let initializeFrame = try server.waitForRequest(method: "initialize")
        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: initializeFrame.requestID,
                    method: "initialize",
                    result: .object([
                        "clientId": .string("notchpilot-test-client"),
                    ]),
                    error: nil
                )
            )
        )

        try server.send(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-live-approval"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-live-approval"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(66),
                                        "params": .object([
                                            "threadId": .string("conv-live-approval"),
                                            "reason": .string("Run date?"),
                                            "command": .string("/bin/zsh -lc date"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                                .string("decline"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-owner-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(surfaceSignal.wait(timeout: .now() + 2), .success)

        let performResult = BooleanBox()
        let performSignal = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            performResult.value = monitor.perform(action: .primary, on: "codex-ipc-66")
            performSignal.signal()
        }

        let outboundFrame = try server.waitForNextFrame()
        guard case let .request(request) = outboundFrame else {
            return XCTFail("expected approval decision request, got \(outboundFrame)")
        }

        XCTAssertEqual(request.method, "thread-follower-command-approval-decision")
        XCTAssertEqual(request.params["conversationId"]?.stringValue, "conv-live-approval")
        XCTAssertEqual(request.params["requestId"], .integer(66))
        XCTAssertEqual(request.params["decision"], .string("accept"))
        XCTAssertEqual(request.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: request.requestID,
                    method: request.method,
                    result: .object([:]),
                    error: nil
                )
            )
        )

        XCTAssertEqual(performSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(performResult.value)
    }

    func testPerformingDirectCommandApprovalFeedbackRepliesThenUsesThreadFollowerFollowUpWithInactiveFallback() throws {
        let server = try TestCodexIPCServer()
        defer { server.stop() }

        let monitor = CodexDesktopMonitor(
            detector: CodexDesktopAppDetector(
                fileManager: .default,
                homeDirectoryURL: server.installedAppHomeDirectoryURL
            ),
            discovery: CodexDesktopIPCDiscovery(directoryURL: server.socketDirectoryURL),
            requestTimeout: 1
        )
        let surfaceSignal = DispatchSemaphore(value: 0)
        monitor.onSurfaceChanged = { surface in
            guard surface?.id == "codex-ipc-approval-feedback-direct" else { return }
            surfaceSignal.signal()
        }

        monitor.start()
        defer { monitor.stop() }

        let initializeFrame = try server.waitForRequest(method: "initialize")
        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: initializeFrame.requestID,
                    method: "initialize",
                    result: .object([
                        "clientId": .string("notchpilot-test-client"),
                    ]),
                    error: nil
                )
            )
        )

        try server.send(
            frame: .request(
                CodexDesktopIPCRequestFrame(
                    requestID: "approval-feedback-direct",
                    method: "item/commandExecution/requestApproval",
                    params: [
                        "threadId": .string("thread-direct-feedback"),
                        "turnId": .string("turn-direct-feedback"),
                        "itemId": .string("item-direct-feedback"),
                        "reason": .string("Run rm -rf?"),
                        "command": .string("rm -rf '/tmp/demo'"),
                        "availableDecisions": .array([
                            .string("accept"),
                            .string("decline"),
                        ]),
                    ],
                    sourceClientID: "desktop-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(surfaceSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(monitor.updateText("Use trash instead.", on: "codex-ipc-approval-feedback-direct"))

        let performResult = BooleanBox()
        let performSignal = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            performResult.value = monitor.perform(action: .primary, on: "codex-ipc-approval-feedback-direct")
            performSignal.signal()
        }

        let responseFrame = try server.waitForNextFrame()
        guard case let .response(response) = responseFrame else {
            return XCTFail("expected approval response, got \(responseFrame)")
        }

        XCTAssertEqual(response.requestID, "approval-feedback-direct")
        XCTAssertEqual(response.method, "item/commandExecution/requestApproval")
        XCTAssertEqual(
            response.result,
            .object([
                "decision": .string("decline"),
            ])
        )
        XCTAssertNil(response.error)

        let steerFrame = try server.waitForNextFrame()
        guard case let .request(steerRequest) = steerFrame else {
            return XCTFail("expected steer request, got \(steerFrame)")
        }

        XCTAssertEqual(steerRequest.method, "thread-follower-steer-turn")
        XCTAssertEqual(steerRequest.params["conversationId"]?.stringValue, "thread-direct-feedback")
        XCTAssertEqual(
            steerRequest.params["input"],
            .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Use trash instead."),
                    "text_elements": .array([]),
                ]),
            ])
        )
        XCTAssertEqual(steerRequest.params["attachments"], .array([]))
        XCTAssertEqual(steerRequest.params["restoreMessage"]?.objectValue?["text"], .string("Use trash instead."))
        XCTAssertEqual(steerRequest.targetClientID, "desktop-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: steerRequest.requestID,
                    method: steerRequest.method,
                    result: nil,
                    error: .string("SteerTurnInactiveError")
                )
            )
        )

        let startTurnFrame = try server.waitForNextFrame()
        guard case let .request(startTurnRequest) = startTurnFrame else {
            return XCTFail("expected start-turn request, got \(startTurnFrame)")
        }

        XCTAssertEqual(startTurnRequest.method, "thread-follower-start-turn")
        XCTAssertEqual(startTurnRequest.params["conversationId"]?.stringValue, "thread-direct-feedback")
        XCTAssertEqual(startTurnRequest.targetClientID, "desktop-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: startTurnRequest.requestID,
                    method: startTurnRequest.method,
                    result: .object([
                        "ok": .bool(true),
                    ]),
                    error: nil
                )
            )
        )

        XCTAssertEqual(performSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(performResult.value)
    }

    func testPerformingLiveCommandApprovalFeedbackSendsDeclineAndFallsBackToStartTurnWhenSteerIsInactive() throws {
        let server = try TestCodexIPCServer()
        defer { server.stop() }

        let monitor = CodexDesktopMonitor(
            detector: CodexDesktopAppDetector(
                fileManager: .default,
                homeDirectoryURL: server.installedAppHomeDirectoryURL
            ),
            discovery: CodexDesktopIPCDiscovery(directoryURL: server.socketDirectoryURL),
            requestTimeout: 1
        )
        let surfaceSignal = DispatchSemaphore(value: 0)
        monitor.onSurfaceChanged = { surface in
            guard surface?.id == "codex-ipc-77" else { return }
            surfaceSignal.signal()
        }

        monitor.start()
        defer { monitor.stop() }

        let initializeFrame = try server.waitForRequest(method: "initialize")
        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: initializeFrame.requestID,
                    method: "initialize",
                    result: .object([
                        "clientId": .string("notchpilot-test-client"),
                    ]),
                    error: nil
                )
            )
        )

        try server.send(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-live-feedback"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-live-feedback"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-live-feedback"),
                                        "status": .string("inProgress"),
                                        "items": .array([]),
                                    ]),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(77),
                                        "params": .object([
                                            "threadId": .string("conv-live-feedback"),
                                            "turnId": .string("turn-live-feedback"),
                                            "reason": .string("Run rm -rf?"),
                                            "command": .string("rm -rf '/tmp/demo'"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                                .string("decline"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-owner-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(surfaceSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(monitor.updateText("Use trash instead.", on: "codex-ipc-77"))

        let performResult = BooleanBox()
        let performSignal = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            performResult.value = monitor.perform(action: .primary, on: "codex-ipc-77")
            performSignal.signal()
        }

        let declineFrame = try server.waitForNextFrame()
        guard case let .request(declineRequest) = declineFrame else {
            return XCTFail("expected decline request, got \(declineFrame)")
        }

        XCTAssertEqual(declineRequest.method, "thread-follower-command-approval-decision")
        XCTAssertEqual(declineRequest.params["conversationId"]?.stringValue, "conv-live-feedback")
        XCTAssertEqual(declineRequest.params["requestId"], .integer(77))
        XCTAssertEqual(declineRequest.params["decision"], .string("decline"))
        XCTAssertEqual(declineRequest.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: declineRequest.requestID,
                    method: declineRequest.method,
                    result: .object([:]),
                    error: nil
                )
            )
        )

        let steerFrame = try server.waitForNextFrame()
        guard case let .request(steerRequest) = steerFrame else {
            return XCTFail("expected steer request, got \(steerFrame)")
        }

        XCTAssertEqual(steerRequest.method, "thread-follower-steer-turn")
        XCTAssertEqual(steerRequest.params["conversationId"]?.stringValue, "conv-live-feedback")
        XCTAssertEqual(
            steerRequest.params["input"],
            .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Use trash instead."),
                    "text_elements": .array([]),
                ]),
            ])
        )
        XCTAssertEqual(steerRequest.params["attachments"], .array([]))
        let restoreMessage = steerRequest.params["restoreMessage"]?.objectValue
        let restoreContext = restoreMessage?["context"]?.objectValue
        XCTAssertEqual(
            restoreMessage?["text"],
            .string("Use trash instead.")
        )
        XCTAssertEqual(
            restoreContext?["prompt"],
            .string("Use trash instead.")
        )
        XCTAssertEqual(
            restoreContext?["workspaceRoots"],
            .array([])
        )
        XCTAssertEqual(
            restoreMessage?["cwd"],
            .null
        )
        XCTAssertEqual(steerRequest.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: steerRequest.requestID,
                    method: steerRequest.method,
                    result: nil,
                    error: .string("SteerTurnInactiveError")
                )
            )
        )

        let startTurnFrame = try server.waitForNextFrame()
        guard case let .request(startTurnRequest) = startTurnFrame else {
            return XCTFail("expected start-turn request, got \(startTurnFrame)")
        }

        XCTAssertEqual(startTurnRequest.method, "thread-follower-start-turn")
        XCTAssertEqual(startTurnRequest.params["conversationId"]?.stringValue, "conv-live-feedback")
        XCTAssertEqual(
            startTurnRequest.params["turnStartParams"],
            .object([
                "input": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Use trash instead."),
                        "text_elements": .array([]),
                    ]),
                ]),
                "cwd": .null,
                "model": .null,
                "effort": .null,
                "approvalPolicy": .null,
                "approvalsReviewer": .string("user"),
                "sandboxPolicy": .null,
                "attachments": .array([]),
                "collaborationMode": .null,
            ])
        )
        XCTAssertEqual(startTurnRequest.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: startTurnRequest.requestID,
                    method: startTurnRequest.method,
                    result: .object([
                        "ok": .bool(true),
                    ]),
                    error: nil
                )
            )
        )

        XCTAssertEqual(performSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(performResult.value)
    }

    func testPerformingLiveCommandApprovalFeedbackStartsTurnDirectlyWhenLatestTurnAlreadyCompleted() throws {
        let server = try TestCodexIPCServer()
        defer { server.stop() }

        let monitor = CodexDesktopMonitor(
            detector: CodexDesktopAppDetector(
                fileManager: .default,
                homeDirectoryURL: server.installedAppHomeDirectoryURL
            ),
            discovery: CodexDesktopIPCDiscovery(directoryURL: server.socketDirectoryURL),
            requestTimeout: 1
        )
        let surfaceSignal = DispatchSemaphore(value: 0)
        monitor.onSurfaceChanged = { surface in
            guard surface?.id == "codex-ipc-78" else { return }
            surfaceSignal.signal()
        }

        monitor.start()
        defer { monitor.stop() }

        let initializeFrame = try server.waitForRequest(method: "initialize")
        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: initializeFrame.requestID,
                    method: "initialize",
                    result: .object([
                        "clientId": .string("notchpilot-test-client"),
                    ]),
                    error: nil
                )
            )
        )

        try server.send(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-live-completed"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-live-completed"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "turns": .array([
                                    .object([
                                        "turnId": .string("turn-live-completed"),
                                        "status": .string("completed"),
                                        "items": .array([]),
                                    ]),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(78),
                                        "params": .object([
                                            "threadId": .string("conv-live-completed"),
                                            "turnId": .string("turn-live-completed"),
                                            "reason": .string("Run rm -rf?"),
                                            "command": .string("rm -rf '/tmp/demo'"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                                .string("decline"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-owner-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(surfaceSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(monitor.updateText("Use trash instead.", on: "codex-ipc-78"))

        let performResult = BooleanBox()
        let performSignal = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            performResult.value = monitor.perform(action: .primary, on: "codex-ipc-78")
            performSignal.signal()
        }

        let declineFrame = try server.waitForNextFrame()
        guard case let .request(declineRequest) = declineFrame else {
            return XCTFail("expected decline request, got \(declineFrame)")
        }

        XCTAssertEqual(declineRequest.method, "thread-follower-command-approval-decision")
        XCTAssertEqual(declineRequest.params["conversationId"]?.stringValue, "conv-live-completed")
        XCTAssertEqual(declineRequest.params["requestId"], .integer(78))
        XCTAssertEqual(declineRequest.params["decision"], .string("decline"))
        XCTAssertEqual(declineRequest.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: declineRequest.requestID,
                    method: declineRequest.method,
                    result: .object([:]),
                    error: nil
                )
            )
        )

        let startTurnFrame = try server.waitForNextFrame()
        guard case let .request(startTurnRequest) = startTurnFrame else {
            return XCTFail("expected start-turn request, got \(startTurnFrame)")
        }

        XCTAssertEqual(startTurnRequest.method, "thread-follower-start-turn")
        XCTAssertEqual(startTurnRequest.params["conversationId"]?.stringValue, "conv-live-completed")
        XCTAssertEqual(
            startTurnRequest.params["turnStartParams"],
            .object([
                "input": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Use trash instead."),
                        "text_elements": .array([]),
                    ]),
                ]),
                "cwd": .null,
                "model": .null,
                "effort": .null,
                "approvalPolicy": .null,
                "approvalsReviewer": .string("user"),
                "sandboxPolicy": .null,
                "attachments": .array([]),
                "collaborationMode": .null,
            ])
        )
        XCTAssertEqual(startTurnRequest.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: startTurnRequest.requestID,
                    method: startTurnRequest.method,
                    result: .object([
                        "ok": .bool(true),
                    ]),
                    error: nil
                )
            )
        )

        XCTAssertEqual(performSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(performResult.value)
    }

    func testPerformingLiveUserInputSendsThreadFollowerSubmitRequest() throws {
        let server = try TestCodexIPCServer()
        defer { server.stop() }

        let monitor = CodexDesktopMonitor(
            detector: CodexDesktopAppDetector(
                fileManager: .default,
                homeDirectoryURL: server.installedAppHomeDirectoryURL
            ),
            discovery: CodexDesktopIPCDiscovery(directoryURL: server.socketDirectoryURL),
            requestTimeout: 1
        )
        let surfaceSignal = DispatchSemaphore(value: 0)
        monitor.onSurfaceChanged = { surface in
            guard surface?.id == "codex-ipc-89" else { return }
            surfaceSignal.signal()
        }

        monitor.start()
        defer { monitor.stop() }

        let initializeFrame = try server.waitForRequest(method: "initialize")
        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: initializeFrame.requestID,
                    method: "initialize",
                    result: .object([
                        "clientId": .string("notchpilot-test-client"),
                    ]),
                    error: nil
                )
            )
        )

        try server.send(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-live-user-input"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-live-user-input"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/tool/requestUserInput"),
                                        "id": .integer(89),
                                        "params": .object([
                                            "threadId": .string("conv-live-user-input"),
                                            "turnId": .string("turn-live-user-input"),
                                            "itemId": .string("item-live-user-input"),
                                            "questions": .array([
                                                .object([
                                                    "id": .string("question-live-input"),
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
                    sourceClientID: "desktop-owner-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(surfaceSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(monitor.updateText("Do not delete the file.", on: "codex-ipc-89"))

        let performResult = BooleanBox()
        let performSignal = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            performResult.value = monitor.perform(action: .primary, on: "codex-ipc-89")
            performSignal.signal()
        }

        let outboundFrame = try server.waitForNextFrame()
        guard case let .request(request) = outboundFrame else {
            return XCTFail("expected user-input submission request, got \(outboundFrame)")
        }

        XCTAssertEqual(request.method, "thread-follower-submit-user-input")
        XCTAssertEqual(request.params["conversationId"]?.stringValue, "conv-live-user-input")
        XCTAssertEqual(request.params["requestId"], .integer(89))
        XCTAssertEqual(
            request.params["response"],
            .object([
                "answers": .object([
                    "question-live-input": .object([
                        "answers": .array([
                            .string("Do not delete the file."),
                        ]),
                    ]),
                ]),
            ])
        )
        XCTAssertEqual(request.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: request.requestID,
                    method: request.method,
                    result: .object([:]),
                    error: nil
                )
            )
        )

        XCTAssertEqual(performSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(performResult.value)
    }
}

private final class BooleanBox: @unchecked Sendable {
    var value = false
}

private final class TestCodexIPCServer: @unchecked Sendable {
    let socketDirectoryURL: URL
    let socketPath: String
    let installedAppHomeDirectoryURL: URL

    private let queue = DispatchQueue(label: "NotchPilot.TestCodexIPCServer")
    private let semaphore = DispatchSemaphore(value: 0)
    private let fileManager = FileManager.default
    private let serverSocket: Int32
    private var clientSocket: Int32 = -1
    private var frames: [CodexDesktopIPCFrame] = []
    private let lock = NSLock()

    init() throws {
        let tempRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("np-\(UUID().uuidString.prefix(8))", isDirectory: true)
        socketDirectoryURL = tempRoot.appendingPathComponent("codex-ipc", isDirectory: true)
        installedAppHomeDirectoryURL = tempRoot
        socketPath = socketDirectoryURL.appendingPathComponent("ipc-test.sock").path

        try fileManager.createDirectory(at: socketDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: tempRoot.appendingPathComponent("Applications", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: tempRoot.appendingPathComponent("Applications/Codex.app", isDirectory: true),
            withIntermediateDirectories: true
        )

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxLength else {
            close(serverSocket)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG))
        }

        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { pathCString in
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    pathCString,
                    maxLength - 1
                )
            }
        }

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(serverSocket, pointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(serverSocket)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }

        guard listen(serverSocket, 1) == 0 else {
            let code = errno
            close(serverSocket)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        if clientSocket >= 0 {
            shutdown(clientSocket, SHUT_RDWR)
            close(clientSocket)
            clientSocket = -1
        }
        shutdown(serverSocket, SHUT_RDWR)
        close(serverSocket)
        try? fileManager.removeItem(at: installedAppHomeDirectoryURL)
    }

    func send(frame: CodexDesktopIPCFrame) throws {
        let data = try CodexDesktopIPCCodec.encode(frame: frame)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            var offset = 0
            while offset < data.count {
                let bytesWritten = Darwin.write(clientSocket, baseAddress.advanced(by: offset), data.count - offset)
                if bytesWritten < 0 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                offset += bytesWritten
            }
        }
    }

    func waitForRequest(method: String, timeout: TimeInterval = 2) throws -> CodexDesktopIPCRequestFrame {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let request = nextFrame(timeout: 0.1).flatMap({ frame -> CodexDesktopIPCRequestFrame? in
                guard case let .request(request) = frame, request.method == method else {
                    return nil
                }
                return request
            }) {
                return request
            }
        }

        XCTFail("timed out waiting for request \(method)")
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
    }

    func waitForNextFrame(timeout: TimeInterval = 2) throws -> CodexDesktopIPCFrame {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let frame = nextFrame(timeout: 0.1) {
                return frame
            }
        }

        XCTFail("timed out waiting for next frame")
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
    }

    private func nextFrame(timeout: TimeInterval) -> CodexDesktopIPCFrame? {
        lock.lock()
        if frames.isEmpty == false {
            let frame = frames.removeFirst()
            lock.unlock()
            return frame
        }
        lock.unlock()

        _ = semaphore.wait(timeout: .now() + timeout)

        lock.lock()
        defer { lock.unlock() }
        guard frames.isEmpty == false else {
            return nil
        }
        return frames.removeFirst()
    }

    private func acceptLoop() {
        let acceptedSocket = Darwin.accept(serverSocket, nil, nil)
        guard acceptedSocket >= 0 else {
            return
        }

        clientSocket = acceptedSocket

        var buffer = Data()
        var tempBuffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let tempBufferCount = tempBuffer.count
            let bytesRead = tempBuffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return 0
                }
                return Darwin.read(acceptedSocket, baseAddress, tempBufferCount)
            }

            if bytesRead <= 0 {
                return
            }

            buffer.append(contentsOf: tempBuffer.prefix(bytesRead))

            do {
                let decodedFrames = try CodexDesktopIPCCodec.decodeFrames(from: &buffer)
                if decodedFrames.isEmpty == false {
                    lock.lock()
                    frames.append(contentsOf: decodedFrames)
                    lock.unlock()
                    for _ in decodedFrames {
                        semaphore.signal()
                    }
                }
            } catch {
                return
            }
        }
    }
}
