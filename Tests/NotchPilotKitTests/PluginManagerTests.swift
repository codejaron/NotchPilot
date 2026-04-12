import SwiftUI
import XCTest
@testable import NotchPilotKit

@MainActor
final class PluginManagerTests: XCTestCase {
    func testDefaultOpenPluginUsesLowestDockOrder() {
        let manager = PluginManager()
        manager.register(PluginManagerTestPlugin(id: "claude", title: "Claude", dockOrder: 100))
        manager.register(PluginManagerTestPlugin(id: "codex", title: "Codex", dockOrder: 110))
        manager.register(PluginManagerTestPlugin(id: "system-monitor", title: "System", dockOrder: 90))

        XCTAssertEqual(
            manager.defaultOpenPluginID(previewPluginID: nil, lastSelectedPluginID: nil),
            "system-monitor"
        )
        XCTAssertEqual(manager.enabledPlugins.map(\.id), ["system-monitor", "claude", "codex"])
    }
}

@MainActor
private final class PluginManagerTestPlugin: NotchPlugin {
    let id: String
    let title: String
    let iconSystemName = "circle"
    let dockOrder: Int
    let accentColor: Color = .blue
    var isEnabled = true
    let previewPriority: Int? = nil

    init(id: String, title: String, dockOrder: Int) {
        self.id = id
        self.title = title
        self.dockOrder = dockOrder
    }

    func preview(context: NotchContext) -> NotchPluginPreview? {
        nil
    }

    func contentView(context: NotchContext) -> AnyView {
        AnyView(EmptyView())
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}
