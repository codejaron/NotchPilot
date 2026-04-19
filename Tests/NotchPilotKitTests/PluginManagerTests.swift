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

    func testActivateAllSkipsDisabledPlugins() {
        let manager = PluginManager()
        let enabled = PluginManagerTestPlugin(id: "enabled", title: "Enabled", dockOrder: 1)
        let disabled = PluginManagerTestPlugin(id: "disabled", title: "Disabled", dockOrder: 2, isEnabled: false)
        let bus = EventBus()

        manager.register(enabled)
        manager.register(disabled)
        manager.activateAll(using: bus)

        XCTAssertEqual(enabled.activateCount, 1)
        XCTAssertEqual(disabled.activateCount, 0)
        XCTAssertEqual(manager.enabledPlugins.map(\.id), ["enabled"])
    }

    func testPluginAvailabilityChangesActivateAndDeactivateRuntime() async {
        let manager = PluginManager()
        let plugin = PluginManagerTestPlugin(id: "runtime", title: "Runtime", dockOrder: 1)
        let bus = EventBus()

        manager.register(plugin)
        manager.activateAll(using: bus)
        XCTAssertEqual(plugin.activateCount, 1)

        plugin.isEnabled = false
        await Task.yield()

        XCTAssertEqual(plugin.deactivateCount, 1)
        XCTAssertTrue(manager.enabledPlugins.isEmpty)

        plugin.isEnabled = true
        await Task.yield()

        XCTAssertEqual(plugin.activateCount, 2)
        XCTAssertEqual(manager.enabledPlugins.map(\.id), ["runtime"])
    }
}

@MainActor
private final class PluginManagerTestPlugin: NotchPlugin {
    let id: String
    let title: String
    let iconSystemName = "circle"
    let dockOrder: Int
    let accentColor: Color = .blue
    @Published var isEnabled: Bool
    let previewPriority: Int? = nil
    private(set) var activateCount = 0
    private(set) var deactivateCount = 0

    init(id: String, title: String, dockOrder: Int, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.dockOrder = dockOrder
        self.isEnabled = isEnabled
    }

    func preview(context: NotchContext) -> NotchPluginPreview? {
        nil
    }

    func contentView(context: NotchContext) -> AnyView {
        AnyView(EmptyView())
    }

    func activate(bus: EventBus) {
        activateCount += 1
    }

    func deactivate() {
        deactivateCount += 1
    }
}
