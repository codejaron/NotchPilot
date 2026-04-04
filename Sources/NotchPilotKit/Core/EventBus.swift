import Foundation

public enum NotchEvent: Equatable, Sendable {
    case sneakPeekRequested(SneakPeekRequest)
    case dismissSneakPeek(requestID: UUID?, target: PresentationTarget)
    case openRequested(pluginID: String, target: PresentationTarget)
    case closeRequested(target: PresentationTarget)
}

@MainActor
public final class EventBus {
    public typealias Handler = (NotchEvent) -> Void

    private var handlers: [UUID: Handler] = [:]

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    public func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    public func emit(_ event: NotchEvent) {
        for handler in handlers.values {
            handler(event)
        }
    }
}
