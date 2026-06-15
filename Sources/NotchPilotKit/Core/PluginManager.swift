import Combine
import Foundation

@MainActor
public final class PluginManager: ObservableObject {
    @Published private var plugins: [any NotchPlugin] = []
    private weak var bus: EventBus?
    private var pluginCancellables: [String: AnyCancellable] = [:]
    private var pluginEnabledStates: [String: Bool] = [:]
    private var activePluginIDs: Set<String> = []
    private let layoutInvalidationSubject = PassthroughSubject<Void, Never>()

    public init() {}

    public var layoutInvalidated: AnyPublisher<Void, Never> {
        layoutInvalidationSubject.eraseToAnyPublisher()
    }

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
        pluginEnabledStates[plugin.id] = plugin.isEnabled
        observe(plugin)
        syncActivation(for: plugin)
        objectWillChange.send()
        layoutInvalidationSubject.send()
    }

    public func activateAll(using bus: EventBus) {
        self.bus = bus
        for plugin in plugins {
            syncActivation(for: plugin)
        }
        objectWillChange.send()
        layoutInvalidationSubject.send()
    }

    public func deactivateAll() {
        for plugin in plugins {
            deactivateIfNeeded(plugin)
        }
        pluginCancellables.removeAll()
        activePluginIDs.removeAll()
        bus = nil
        objectWillChange.send()
        layoutInvalidationSubject.send()
    }

    public func plugin(id: String) -> (any NotchPlugin)? {
        enabledPlugins.first(where: { $0.id == id })
    }

    public func registeredPlugin(id: String) -> (any NotchPlugin)? {
        plugins.first(where: { $0.id == id })
    }

    public func resolvedTabID(_ rawID: String?) -> String? {
        NotchPluginTabCollection(plugins: enabledPlugins).resolvedTabID(rawID)
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
        let tabs = NotchPluginTabCollection(plugins: enabledPlugins)

        if let previewPluginID,
           let resolvedID = tabs.resolvedAvailableTabID(previewPluginID) {
            return resolvedID
        }

        if let lastSelectedPluginID,
           let resolvedID = tabs.resolvedAvailableTabID(lastSelectedPluginID) {
            return resolvedID
        }

        return tabs.defaultTabID
    }

    private func observe(_ plugin: any NotchPlugin) {
        pluginCancellables[plugin.id] = plugin.objectWillChange.sink { [weak self, plugin] (_: Void) in
            Task { @MainActor [weak self, plugin] in
                let wasEnabled = self?.pluginEnabledStates[plugin.id]
                self?.syncActivation(for: plugin)
                self?.pluginEnabledStates[plugin.id] = plugin.isEnabled
                self?.objectWillChange.send()
                if wasEnabled != plugin.isEnabled {
                    self?.layoutInvalidationSubject.send()
                }
            }
        }
    }

    private func syncActivation(for plugin: any NotchPlugin) {
        guard let bus else {
            return
        }

        if plugin.isEnabled {
            guard activePluginIDs.insert(plugin.id).inserted else {
                return
            }
            plugin.activate(bus: bus)
        } else {
            deactivateIfNeeded(plugin)
        }
    }

    private func deactivateIfNeeded(_ plugin: any NotchPlugin) {
        guard activePluginIDs.remove(plugin.id) != nil else {
            return
        }

        plugin.deactivate()
    }
}
