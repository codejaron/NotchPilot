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

@MainActor
public protocol NotchPlugin: AnyObject, Identifiable, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var id: String { get }
    var title: String { get }
    var iconSystemName: String { get }
    var accentColor: Color { get }
    var isEnabled: Bool { get set }
    var dockOrder: Int { get }
    var previewPriority: Int? { get }

    func preview(context: NotchContext) -> NotchPluginPreview?
    func contentView(context: NotchContext) -> AnyView
    func activate(bus: EventBus)
    func deactivate()
}

public extension NotchPlugin {
    var previewPriority: Int? { nil }

    func preview(context: NotchContext) -> NotchPluginPreview? { nil }
}
