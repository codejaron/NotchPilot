import Foundation

@MainActor
protocol AIBridgeFrameHandling: AnyObject {
    func canHandleBridgeFrame(host: AIHost) -> Bool
    func handle(frame: BridgeFrame, respond: @escaping @Sendable (Data) -> Void)
    func handleDisconnect(requestID: String)
}

@MainActor
final class AIBridgeDispatcher {
    private let handlers: [any AIBridgeFrameHandling]

    init(handlers: [any AIBridgeFrameHandling]) {
        self.handlers = handlers
    }

    func handle(frame: BridgeFrame, respond: @escaping @Sendable (Data) -> Void) {
        guard let handler = handlers.first(where: { $0.canHandleBridgeFrame(host: frame.host) }) else {
            respond(Data("{}".utf8))
            return
        }

        handler.handle(frame: frame, respond: respond)
    }

    func handleDisconnect(requestID: String) {
        for handler in handlers {
            handler.handleDisconnect(requestID: requestID)
        }
    }
}
