import Foundation

public final class SneakPeekQueue {
    private struct Entry {
        let request: SneakPeekRequest
        let sequence: Int
    }

    private var entries: [Entry] = []
    private var nextSequence = 0

    public init() {}

    public var current: SneakPeekRequest? {
        orderedEntries.first?.request
    }

    public var requests: [SneakPeekRequest] {
        orderedEntries.map(\.request)
    }

    public func enqueue(_ request: SneakPeekRequest) {
        entries.append(Entry(request: request, sequence: nextSequence))
        nextSequence += 1
    }

    @discardableResult
    public func dismissCurrent() -> SneakPeekRequest? {
        guard let current else {
            return nil
        }

        return remove(id: current.id)
    }

    @discardableResult
    public func expire(_ id: UUID) -> SneakPeekRequest? {
        remove(id: id)
    }

    @discardableResult
    private func remove(id: UUID) -> SneakPeekRequest? {
        guard let index = entries.firstIndex(where: { $0.request.id == id }) else {
            return nil
        }

        return entries.remove(at: index).request
    }

    private var orderedEntries: [Entry] {
        entries.sorted {
            if $0.request.priority == $1.request.priority {
                return $0.sequence < $1.sequence
            }

            return $0.request.priority > $1.request.priority
        }
    }
}
