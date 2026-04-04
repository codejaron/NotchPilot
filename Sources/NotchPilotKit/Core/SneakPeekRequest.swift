import Foundation

public struct SneakPeekRequest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let pluginID: String
    public let priority: Int
    public let target: PresentationTarget
    public let isInteractive: Bool
    public let autoDismissAfter: TimeInterval?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        pluginID: String,
        priority: Int,
        target: PresentationTarget,
        isInteractive: Bool,
        autoDismissAfter: TimeInterval?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pluginID = pluginID
        self.priority = priority
        self.target = target
        self.isInteractive = isInteractive
        self.autoDismissAfter = autoDismissAfter
        self.createdAt = createdAt
    }
}
