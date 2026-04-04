import CoreGraphics
import Foundation

public struct ScreenDescriptor: Equatable, Sendable, Identifiable {
    public let id: String
    public let frame: CGRect
    public let isPrimary: Bool
    public let closedNotchSize: CGSize?

    public init(id: String, frame: CGRect, isPrimary: Bool, closedNotchSize: CGSize? = nil) {
        self.id = id
        self.frame = frame
        self.isPrimary = isPrimary
        self.closedNotchSize = closedNotchSize
    }
}

public struct ScreenResolutionContext: Equatable, Sendable {
    public let connectedScreens: [ScreenDescriptor]
    public let activeScreenID: String?
    public let primaryScreenID: String?

    public init(
        connectedScreens: [ScreenDescriptor],
        activeScreenID: String?,
        primaryScreenID: String?
    ) {
        self.connectedScreens = connectedScreens
        self.activeScreenID = activeScreenID
        self.primaryScreenID = primaryScreenID
    }
}

public enum PresentationTargetResolver {
    public static func resolve(_ target: PresentationTarget, in context: ScreenResolutionContext) -> [String] {
        switch target {
        case .allScreens:
            return context.connectedScreens.map(\.id)
        case .activeScreen:
            return [fallbackScreenID(in: context, preferred: context.activeScreenID)].compactMap { $0 }
        case .primaryScreen:
            return [fallbackScreenID(in: context, preferred: context.primaryScreenID ?? context.activeScreenID)].compactMap { $0 }
        case let .screen(id):
            if context.connectedScreens.contains(where: { $0.id == id }) {
                return [id]
            }
            return [fallbackScreenID(in: context, preferred: context.activeScreenID ?? context.primaryScreenID)].compactMap { $0 }
        }
    }

    private static func fallbackScreenID(in context: ScreenResolutionContext, preferred: String?) -> String? {
        if let preferred, context.connectedScreens.contains(where: { $0.id == preferred }) {
            return preferred
        }

        if let active = context.activeScreenID, context.connectedScreens.contains(where: { $0.id == active }) {
            return active
        }

        if let primary = context.primaryScreenID, context.connectedScreens.contains(where: { $0.id == primary }) {
            return primary
        }

        return context.connectedScreens.first?.id
    }
}
