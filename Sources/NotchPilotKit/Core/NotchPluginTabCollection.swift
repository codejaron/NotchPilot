import SwiftUI

@MainActor
struct NotchPluginTabCollection {
    @MainActor
    struct Group {
        let metadata: NotchPluginTabGroup
        let members: [any NotchPlugin]

        var id: String { metadata.id }
        var title: String { metadata.title }
        var iconSystemName: String { metadata.iconSystemName }
        var dockOrder: Int { members.map { $0.dockOrder }.min() ?? Int.max }
        var accentColor: Color { members.min { $0.dockOrder < $1.dockOrder }?.accentColor ?? .accentColor }
        var renderer: (any NotchPluginTabGroupRendering)? {
            members.compactMap { $0 as? any NotchPluginTabGroupRendering }.first
        }

        func contentView(context: NotchContext) -> AnyView? {
            if let renderer {
                return renderer.tabGroupContentView(members: members, context: context)
            }
            return members.first.map { $0.contentView(context: context) }
        }

        func headerAccessory() -> AnyView? {
            renderer?.tabGroupHeaderAccessory(members: members)
        }
    }

    let pluginTabs: [any NotchPlugin]
    let groupTabs: [Group]

    private let tabIDByMemberID: [String: String]

    init(plugins: [any NotchPlugin]) {
        var pluginTabs: [any NotchPlugin] = []
        var groupedPlugins: [String: (metadata: NotchPluginTabGroup, members: [any NotchPlugin])] = [:]
        var tabIDByMemberID: [String: String] = [:]

        for plugin in plugins {
            guard let group = plugin.tabGroup else {
                pluginTabs.append(plugin)
                continue
            }

            if var existing = groupedPlugins[group.id] {
                existing.members.append(plugin)
                groupedPlugins[group.id] = existing
            } else {
                groupedPlugins[group.id] = (metadata: group, members: [plugin])
            }

            tabIDByMemberID[group.id] = group.id
            tabIDByMemberID[plugin.id] = group.id
            for memberPluginID in group.memberPluginIDs {
                tabIDByMemberID[memberPluginID] = group.id
            }
        }

        self.pluginTabs = pluginTabs
        self.groupTabs = groupedPlugins.values.map {
            Group(metadata: $0.metadata, members: $0.members)
        }
        self.tabIDByMemberID = tabIDByMemberID
    }

    var orderedTabIDs: [String] {
        let pluginTabs = pluginTabs.map {
            (order: $0.dockOrder, title: $0.title, id: $0.id)
        }
        let groupTabs = groupTabs.map {
            (order: $0.dockOrder, title: $0.title, id: $0.id)
        }

        return (pluginTabs + groupTabs)
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.title < rhs.title
                }
                return lhs.order < rhs.order
            }
            .map(\.id)
    }

    var defaultTabID: String? {
        orderedTabIDs.first
    }

    func resolvedTabID(_ rawID: String?) -> String? {
        guard let rawID else {
            return nil
        }
        return tabIDByMemberID[rawID] ?? rawID
    }

    func resolvedAvailableTabID(_ rawID: String?) -> String? {
        guard let resolvedID = resolvedTabID(rawID) else {
            return nil
        }
        return containsTab(id: resolvedID) ? resolvedID : nil
    }

    func containsTab(id: String) -> Bool {
        plugin(id: id) != nil || group(id: id) != nil
    }

    func plugin(id: String) -> (any NotchPlugin)? {
        pluginTabs.first { $0.id == id }
    }

    func group(id: String) -> Group? {
        groupTabs.first { $0.id == id }
    }
}
