import Foundation

public enum SneakPeekRequestKind: Equatable, Sendable {
    case activity
    case attention
}

public enum SneakPeekRequestPriority {
    public static let ai = 100
    public static let mediaPlayback = 700
    public static let systemMonitor = 2_000
}

public struct SneakPeekRequest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let pluginID: String
    public let priority: Int
    public let target: PresentationTarget
    public let kind: SneakPeekRequestKind
    public let isInteractive: Bool
    public let autoDismissAfter: TimeInterval?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        pluginID: String,
        priority: Int,
        target: PresentationTarget,
        kind: SneakPeekRequestKind = .activity,
        isInteractive: Bool,
        autoDismissAfter: TimeInterval?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pluginID = pluginID
        self.priority = priority
        self.target = target
        self.kind = kind
        self.isInteractive = isInteractive
        self.autoDismissAfter = autoDismissAfter
        self.createdAt = createdAt
    }
}
