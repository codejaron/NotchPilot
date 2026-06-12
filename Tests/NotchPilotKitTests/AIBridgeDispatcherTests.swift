import XCTest
@testable import NotchPilotKit

final class AIBridgeDispatcherTests: XCTestCase {
    @MainActor
    func testDispatcherRoutesFrameToFirstMatchingHandler() {
        let claudeHandler = TestBridgeFrameHandler(hosts: [.claude], response: "claude")
        let codexHandler = TestBridgeFrameHandler(hosts: [.codex], response: "codex")
        let dispatcher = AIBridgeDispatcher(handlers: [claudeHandler, codexHandler])
        let responseBox = TestBridgeResponseBox()

        dispatcher.handle(
            frame: BridgeFrame(host: .codex, requestID: "codex-request", rawJSON: "{}"),
            respond: { responseBox.set($0) }
        )

        XCTAssertTrue(claudeHandler.handledFrames.isEmpty)
        XCTAssertEqual(codexHandler.handledFrames.map(\.requestID), ["codex-request"])
        XCTAssertEqual(String(data: responseBox.data ?? Data(), encoding: .utf8), "codex")
    }

    @MainActor
    func testDispatcherRespondsWithEmptyObjectWhenNoHandlerMatches() {
        let dispatcher = AIBridgeDispatcher(
            handlers: [TestBridgeFrameHandler(hosts: [.claude], response: "claude")]
        )
        let responseBox = TestBridgeResponseBox()

        dispatcher.handle(
            frame: BridgeFrame(host: .codex, requestID: "codex-request", rawJSON: "{}"),
            respond: { responseBox.set($0) }
        )

        XCTAssertEqual(String(data: responseBox.data ?? Data(), encoding: .utf8), "{}")
    }

    @MainActor
    func testDispatcherBroadcastsDisconnectToHandlers() {
        let first = TestBridgeFrameHandler(hosts: [.claude], response: "claude")
        let second = TestBridgeFrameHandler(hosts: [.codex], response: "codex")
        let dispatcher = AIBridgeDispatcher(handlers: [first, second])

        dispatcher.handleDisconnect(requestID: "pending-request")

        XCTAssertEqual(first.disconnectedRequestIDs, ["pending-request"])
        XCTAssertEqual(second.disconnectedRequestIDs, ["pending-request"])
    }
}

@MainActor
private final class TestBridgeFrameHandler: AIBridgeFrameHandling {
    private let hosts: [AIHost]
    private let response: String
    private(set) var handledFrames: [BridgeFrame] = []
    private(set) var disconnectedRequestIDs: [String] = []

    init(hosts: [AIHost], response: String) {
        self.hosts = hosts
        self.response = response
    }

    func canHandleBridgeFrame(host: AIHost) -> Bool {
        hosts.contains(host)
    }

    func handle(frame: BridgeFrame, respond: @escaping @Sendable (Data) -> Void) {
        handledFrames.append(frame)
        respond(Data(response.utf8))
    }

    func handleDisconnect(requestID: String) {
        disconnectedRequestIDs.append(requestID)
    }
}

private final class TestBridgeResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?

    var data: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }

    func set(_ data: Data) {
        lock.lock()
        storedData = data
        lock.unlock()
    }
}
