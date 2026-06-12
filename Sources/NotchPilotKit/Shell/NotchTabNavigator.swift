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
        NotchPluginTabCollection(plugins: plugins).orderedTabIDs
    }

    static func orderedTabIDs(
        pluginTabs: [Tab],
        groupTabs: [Tab]
    ) -> [String] {
        var tabs = pluginTabs.map { tab in
            (order: tab.dockOrder, title: tab.title, id: tab.id)
        }

        for groupTab in groupTabs {
            tabs.append((order: groupTab.dockOrder, title: groupTab.title, id: groupTab.id))
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
        direction: Direction,
        resolveTabID: (String?) -> String? = { $0 }
    ) -> String? {
        guard orderedTabIDs.count > 1 else {
            return nil
        }

        let resolvedCurrentID = resolveTabID(currentID)
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
