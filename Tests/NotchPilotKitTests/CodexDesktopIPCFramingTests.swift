import XCTest
@testable import NotchPilotKit

final class CodexDesktopIPCFramingTests: XCTestCase {
    func testEncodeAndDecodeSingleRequestFrame() throws {
        let frame = CodexDesktopIPCFrame.request(
            CodexDesktopIPCRequestFrame(
                requestID: "req-1",
                method: "initialize",
                params: [
                    "clientType": .string("notchpilot"),
                ],
                sourceClientID: "initializing-client",
                targetClientID: nil,
                version: 1
            )
        )

        var buffer = try CodexDesktopIPCCodec.encode(frame: frame)
        let decoded = try CodexDesktopIPCCodec.decodeFrames(from: &buffer)

        XCTAssertEqual(decoded, [frame])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDecodeFramesLeavesIncompleteTailBuffered() throws {
        let first = CodexDesktopIPCFrame.broadcast(
            CodexDesktopIPCBroadcastFrame(
                method: "thread-stream-state-changed",
                params: [
                    "conversationId": .string("thr-1"),
                ],
                sourceClientID: "desktop-client",
                targetClientID: nil,
                version: 1
            )
        )

        let second = CodexDesktopIPCFrame.response(
            CodexDesktopIPCResponseFrame(
                requestID: "req-2",
                method: "initialize",
                result: .object([
                    "clientId": .string("desktop-sidecar"),
                ]),
                error: nil
            )
        )

        let encodedFirst = try CodexDesktopIPCCodec.encode(frame: first)
        let encodedSecond = try CodexDesktopIPCCodec.encode(frame: second)
        let splitIndex = encodedSecond.count - 3

        var buffer = encodedFirst
        buffer.append(encodedSecond.prefix(splitIndex))

        let partial = try CodexDesktopIPCCodec.decodeFrames(from: &buffer)
        XCTAssertEqual(partial, [first])
        XCTAssertFalse(buffer.isEmpty)

        buffer.append(encodedSecond.suffix(3))
        let final = try CodexDesktopIPCCodec.decodeFrames(from: &buffer)
        XCTAssertEqual(final, [second])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDecodeClientDiscoveryRequestPreservesNestedRequest() throws {
        let payload: [String: Any] = [
            "type": "client-discovery-request",
            "requestId": "discovery-1",
            "request": [
                "type": "request",
                "requestId": "req-1",
                "method": "item/commandExecution/requestApproval",
                "params": [
                    "threadId": "thr-1",
                ],
                "sourceClientId": "desktop-client",
                "version": 1,
            ],
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        var buffer = Data(count: 4)
        buffer.withUnsafeMutableBytes { rawBuffer in
            rawBuffer.storeBytes(of: UInt32(payloadData.count).littleEndian, as: UInt32.self)
        }
        buffer.append(payloadData)

        let frames = try CodexDesktopIPCCodec.decodeFrames(from: &buffer)

        guard case let .clientDiscoveryRequest(requestID, request)? = frames.first else {
            return XCTFail("expected client discovery request")
        }

        XCTAssertEqual(requestID, "discovery-1")
        XCTAssertEqual(request?.method, "item/commandExecution/requestApproval")
        XCTAssertEqual(request?.params["threadId"]?.stringValue, "thr-1")
    }

    func testDecodeLiveApprovalPatchPreservesArrayIndexAndReducerEmitsApproval() throws {
        let clearPayload: [String: Any] = [
            "type": "broadcast",
            "method": "thread-stream-state-changed",
            "params": [
                "conversationId": "conv-live-raw",
                "change": [
                    "type": "patches",
                    "patches": [
                        [
                            "op": "replace",
                            "path": ["requests"],
                            "value": [],
                        ],
                    ],
                ],
            ],
            "sourceClientId": "desktop-client",
            "version": 1,
        ]

        let addPayload: [String: Any] = [
            "type": "broadcast",
            "method": "thread-stream-state-changed",
            "params": [
                "conversationId": "conv-live-raw",
                "change": [
                    "type": "patches",
                    "patches": [
                        [
                            "op": "add",
                            "path": ["requests", 0],
                            "value": [
                                "method": "item/commandExecution/requestApproval",
                                "id": 96,
                                "params": [
                                    "threadId": "conv-live-raw",
                                    "turnId": "turn-live-raw",
                                    "itemId": "item-live-raw",
                                    "reason": "Do you want to approve deleting the temporary directory I just created for this test?",
                                    "command": "/bin/zsh -lc \"rm -rf '/tmp/live-raw'\"",
                                    "cwd": "/tmp",
                                    "commandActions": [
                                        [
                                            "type": "unknown",
                                            "command": "rm -rf '/tmp/live-raw'",
                                        ],
                                    ],
                                    "proposedExecpolicyAmendment": [
                                        "rm",
                                        "-rf",
                                        "/tmp/live-raw",
                                    ],
                                    "availableDecisions": [
                                        "accept",
                                        [
                                            "acceptWithExecpolicyAmendment": [
                                                "execpolicy_amendment": [
                                                    "rm",
                                                    "-rf",
                                                    "/tmp/live-raw",
                                                ],
                                            ],
                                        ],
                                        "cancel",
                                    ],
                                ],
                            ],
                        ],
                        [
                            "op": "replace",
                            "path": ["hasUnreadTurn"],
                            "value": true,
                        ],
                    ],
                ],
            ],
            "sourceClientId": "desktop-client",
            "version": 1,
        ]

        var clearBuffer = Data(count: 4)
        let clearPayloadData = try JSONSerialization.data(withJSONObject: clearPayload, options: [])
        clearBuffer.withUnsafeMutableBytes { rawBuffer in
            rawBuffer.storeBytes(of: UInt32(clearPayloadData.count).littleEndian, as: UInt32.self)
        }
        clearBuffer.append(clearPayloadData)

        var addBuffer = Data(count: 4)
        let addPayloadData = try JSONSerialization.data(withJSONObject: addPayload, options: [])
        addBuffer.withUnsafeMutableBytes { rawBuffer in
            rawBuffer.storeBytes(of: UInt32(addPayloadData.count).littleEndian, as: UInt32.self)
        }
        addBuffer.append(addPayloadData)

        let clearFrames = try CodexDesktopIPCCodec.decodeFrames(from: &clearBuffer)
        let addFrames = try CodexDesktopIPCCodec.decodeFrames(from: &addBuffer)

        guard case let .broadcast(addBroadcast)? = addFrames.first else {
            return XCTFail("expected add broadcast frame")
        }

        let addPatches = addBroadcast.params.objectValue(at: ["change"])?.arrayValue(at: ["patches"])
        let addPath = addPatches?.first?.objectValue?.arrayValue(at: ["path"])
        XCTAssertEqual(addPath?.count, 2)
        XCTAssertEqual(addPath?.first?.stringValue, "requests")
        XCTAssertEqual(addPath?.dropFirst().first?.integerValue, 0)

        var reducer = CodexDesktopEventReducer()
        for frame in clearFrames {
            _ = try reducer.consume(frame: frame)
        }

        let outputs = try addFrames.flatMap { try reducer.consume(frame: $0) }

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

        XCTAssertEqual(request?.requestID, "96")
        XCTAssertEqual(request?.method, "item/commandExecution/requestApproval")
    }
}
