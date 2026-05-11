import Combine
import Foundation

@MainActor
public final class NotificationHistoryStore: ObservableObject {
    public struct HistoryEntry: Identifiable, Equatable, Hashable {
        public let notification: SystemNotification
        public let muted: Bool

        public var id: UUID { notification.id }
    }

    @Published public private(set) var entries: [HistoryEntry] = []
    public let limit: Int

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public func append(_ notification: SystemNotification, muted: Bool) {
        let entry = HistoryEntry(notification: notification, muted: muted)
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func clear() {
        entries.removeAll()
    }

    public var groupedByApp: [(bundleID: String, entries: [HistoryEntry])] {
        var buckets: [String: [HistoryEntry]] = [:]
        for entry in entries {
            buckets[entry.notification.bundleIdentifier, default: []].append(entry)
        }
        for key in buckets.keys {
            buckets[key]?.sort { $0.notification.deliveredAt > $1.notification.deliveredAt }
        }
        return buckets
            .map { (bundleID: $0.key, entries: $0.value) }
            .sorted { lhs, rhs in
                let lhsLatest = lhs.entries.first?.notification.deliveredAt ?? .distantPast
                let rhsLatest = rhs.entries.first?.notification.deliveredAt ?? .distantPast
                return lhsLatest > rhsLatest
            }
    }
}
