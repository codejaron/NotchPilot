import SwiftUI

@MainActor
public protocol NotchPlugin: AnyObject, Identifiable, ObservableObject {
    var id: String { get }
    var name: String { get }
    var iconSystemName: String { get }
    var isEnabled: Bool { get set }
    var priority: Int { get }

    func compactView(context: NotchContext) -> AnyView?
    func compactWidth(context: NotchContext) -> CGFloat?
    func sneakPeekView(context: NotchContext) -> AnyView?
    func sneakPeekWidth(context: NotchContext) -> CGFloat?
    func expandedView(context: NotchContext) -> AnyView
    func activate(bus: EventBus)
    func deactivate()
}

public extension NotchPlugin {
    func compactWidth(context: NotchContext) -> CGFloat? { nil }
    func sneakPeekWidth(context: NotchContext) -> CGFloat? { nil }
}
