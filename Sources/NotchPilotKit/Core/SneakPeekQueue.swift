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
        current(at: Date())
    }

    public var requests: [SneakPeekRequest] {
        requests(at: Date())
    }

    public func enqueue(_ request: SneakPeekRequest) {
        entries.append(Entry(request: request, sequence: nextSequence))
        nextSequence += 1
    }

    public func current(at date: Date) -> SneakPeekRequest? {
        pruneExpired(now: date)
        return orderedEntries.first?.request
    }

    public func requests(at date: Date) -> [SneakPeekRequest] {
        pruneExpired(now: date)
        return orderedEntries.map(\.request)
    }

    public func updatePriority(
        requestID: UUID,
        priority: Int
    ) -> SneakPeekRequest? {
        guard let index = entries.firstIndex(where: { $0.request.id == requestID }) else {
            return nil
        }

        let existing = entries[index]
        let updated = SneakPeekRequest(
            id: existing.request.id,
            pluginID: existing.request.pluginID,
            priority: priority,
            target: existing.request.target,
            kind: existing.request.kind,
            isInteractive: existing.request.isInteractive,
            autoDismissAfter: existing.request.autoDismissAfter,
            createdAt: existing.request.createdAt
        )
        entries[index] = Entry(request: updated, sequence: existing.sequence)
        return updated
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

            return $0.request.priority < $1.request.priority
        }
    }

    private func isExpired(_ request: SneakPeekRequest, now: Date) -> Bool {
        guard let autoDismissAfter = request.autoDismissAfter else {
            return false
        }
        return now.timeIntervalSince(request.createdAt) >= autoDismissAfter
    }

    private func pruneExpired(now: Date) {
        entries.removeAll { isExpired($0.request, now: now) }
    }
}
