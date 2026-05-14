import CoreGraphics
import Foundation

public struct NotchGeometry: Equatable, Sendable {
    public let compactSize: CGSize
    public let expandedSize: CGSize

    public init(compactSize: CGSize, expandedSize: CGSize) {
        self.compactSize = compactSize
        self.expandedSize = expandedSize
    }
}

public struct NotchContext: Equatable, Sendable {
    public let screenID: String
    public let notchState: NotchState
    public let notchGeometry: NotchGeometry
    public let isPrimaryScreen: Bool
    public let currentSneakPeek: SneakPeekRequest?

    public init(
        screenID: String,
        notchState: NotchState,
        notchGeometry: NotchGeometry,
        isPrimaryScreen: Bool,
        currentSneakPeek: SneakPeekRequest? = nil
    ) {
        self.screenID = screenID
        self.notchState = notchState
        self.notchGeometry = notchGeometry
        self.isPrimaryScreen = isPrimaryScreen
        self.currentSneakPeek = currentSneakPeek
    }
}
