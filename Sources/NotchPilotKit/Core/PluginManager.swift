import Combine
import Foundation

@MainActor
public final class PluginManager: ObservableObject {
    @Published private var plugins: [any NotchPlugin] = []
    private weak var bus: EventBus?

    public init() {}

    public var enabledPlugins: [any NotchPlugin] {
        plugins
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.name < rhs.name
                }
                return lhs.priority > rhs.priority
            }
    }

    public func register(_ plugin: any NotchPlugin) {
        plugins.append(plugin)
        if let bus {
            plugin.activate(bus: bus)
        }
        objectWillChange.send()
    }

    public func activateAll(using bus: EventBus) {
        self.bus = bus
        for plugin in plugins {
            plugin.activate(bus: bus)
        }
        objectWillChange.send()
    }

    public func deactivateAll() {
        for plugin in plugins {
            plugin.deactivate()
        }
        bus = nil
        objectWillChange.send()
    }

    public func plugin(id: String) -> (any NotchPlugin)? {
        enabledPlugins.first(where: { $0.id == id })
    }
}
