import Combine
import SwiftUI

public struct NotchPluginPreview {
    public let width: CGFloat
    public let height: CGFloat?
    public let view: AnyView

    public init(width: CGFloat, height: CGFloat? = nil, view: AnyView) {
        self.width = width
        self.height = height
        self.view = view
    }
}

public struct NotchPluginTabGroup {
    public let id: String
    public let title: String
    public let iconSystemName: String
    public let memberPluginIDs: Set<String>

    public init(
        id: String,
        title: String,
        iconSystemName: String,
        memberPluginIDs: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.memberPluginIDs = memberPluginIDs
    }
}

@MainActor
protocol NotchPluginTabGroupRendering: AnyObject {
    func tabGroupContentView(members: [any NotchPlugin], context: NotchContext) -> AnyView
    func tabGroupHeaderAccessory(members: [any NotchPlugin]) -> AnyView?
}

extension NotchPluginTabGroupRendering {
    func tabGroupHeaderAccessory(members: [any NotchPlugin]) -> AnyView? { nil }
}

@MainActor
public protocol NotchPlugin: AnyObject, Identifiable, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var id: String { get }
    var title: String { get }
    var iconSystemName: String { get }
    var accentColor: Color { get }
    var isEnabled: Bool { get set }
    var dockOrder: Int { get }
    var previewPriority: Int? { get }
    var tabGroup: NotchPluginTabGroup? { get }

    func preview(context: NotchContext) -> NotchPluginPreview?
    func contentView(context: NotchContext) -> AnyView
    func activate(bus: EventBus)
    func deactivate()
}

public extension NotchPlugin {
    var previewPriority: Int? { nil }
    var tabGroup: NotchPluginTabGroup? { nil }

    func preview(context: NotchContext) -> NotchPluginPreview? { nil }
}
