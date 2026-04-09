import Combine
import Foundation

@MainActor
public final class PluginManager: ObservableObject {
    @Published private var plugins: [any NotchPlugin] = []
    private weak var bus: EventBus?
    private var pluginCancellables: [String: AnyCancellable] = [:]

    public init() {}

    public var enabledPlugins: [any NotchPlugin] {
        plugins
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.dockOrder == rhs.dockOrder {
                    return lhs.title < rhs.title
                }
                return lhs.dockOrder < rhs.dockOrder
            }
    }

    public func register(_ plugin: any NotchPlugin) {
        plugins.append(plugin)
        observe(plugin)
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
        pluginCancellables.removeAll()
        bus = nil
        objectWillChange.send()
    }

    public func plugin(id: String) -> (any NotchPlugin)? {
        enabledPlugins.first(where: { $0.id == id })
    }

    public func previewPlugin(
        for request: SneakPeekRequest?,
        context: NotchContext
    ) -> (any NotchPlugin)? {
        if let request,
           let preferred = plugin(id: request.pluginID),
           preferred.preview(context: context) != nil {
            return preferred
        }

        return enabledPlugins
            .filter { $0.preview(context: context) != nil }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.previewPriority ?? Int.max
                let rhsPriority = rhs.previewPriority ?? Int.max

                if lhsPriority == rhsPriority {
                    if lhs.dockOrder == rhs.dockOrder {
                        return lhs.title < rhs.title
                    }
                    return lhs.dockOrder < rhs.dockOrder
                }

                return lhsPriority < rhsPriority
            }
            .first
    }

    public func defaultOpenPluginID(
        previewPluginID: String?,
        lastSelectedPluginID: String?
    ) -> String? {
        if let previewPluginID,
           enabledPlugins.contains(where: { $0.id == previewPluginID }) {
            return previewPluginID
        }

        if let lastSelectedPluginID,
           enabledPlugins.contains(where: { $0.id == lastSelectedPluginID }) {
            return lastSelectedPluginID
        }

        return enabledPlugins.first?.id
    }

    private func observe(_ plugin: any NotchPlugin) {
        pluginCancellables[plugin.id] = plugin.objectWillChange.sink { [weak self] (_: Void) in
            self?.objectWillChange.send()
        }
    }
}
