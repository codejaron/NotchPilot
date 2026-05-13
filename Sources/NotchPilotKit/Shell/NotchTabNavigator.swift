import Foundation

@MainActor
enum NotchTabNavigator {
    enum Direction {
        case previous
        case next
    }

    struct Tab: Equatable {
        let id: String
        let title: String
        let dockOrder: Int
    }

    static func orderedTabIDs(from plugins: [any NotchPlugin]) -> [String] {
        let aiPlugins = AIPluginGroup.aiPlugins(from: plugins)
        return orderedTabIDs(
            pluginTabs: AIPluginGroup.nonAIPlugins(from: plugins).map {
                Tab(id: $0.id, title: $0.title, dockOrder: $0.dockOrder)
            },
            aiTabDockOrder: aiPlugins.isEmpty ? nil : AIPluginGroup.dockOrder(of: aiPlugins)
        )
    }

    static func orderedTabIDs(
        pluginTabs: [Tab],
        aiTabDockOrder: Int?
    ) -> [String] {
        var tabs = pluginTabs.map { tab in
            (order: tab.dockOrder, title: tab.title, id: tab.id)
        }

        if let aiTabDockOrder {
            tabs.append((order: aiTabDockOrder, title: "AI", id: AIPluginGroup.virtualTabID))
        }

        return tabs
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.title < rhs.title
                }
                return lhs.order < rhs.order
            }
            .map(\.id)
    }

    static func destination(
        from currentID: String?,
        orderedTabIDs: [String],
        direction: Direction
    ) -> String? {
        guard orderedTabIDs.count > 1 else {
            return nil
        }

        let resolvedCurrentID = AIPluginGroup.resolvedActivePluginID(currentID)
        guard
            let resolvedCurrentID,
            let currentIndex = orderedTabIDs.firstIndex(of: resolvedCurrentID)
        else {
            return orderedTabIDs.first
        }

        switch direction {
        case .previous:
            let previousIndex = currentIndex == orderedTabIDs.startIndex
                ? orderedTabIDs.index(before: orderedTabIDs.endIndex)
                : orderedTabIDs.index(before: currentIndex)
            return orderedTabIDs[previousIndex]
        case .next:
            let nextIndex = orderedTabIDs.index(after: currentIndex)
            return nextIndex == orderedTabIDs.endIndex
                ? orderedTabIDs[orderedTabIDs.startIndex]
                : orderedTabIDs[nextIndex]
        }
    }
}
