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
}
