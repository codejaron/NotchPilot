import Foundation

/// AI-owned metadata for treating Claude, Codex, and Devin-facing surfaces as one
/// tab group. Core and Shell consume the generic `NotchPluginTabGroup` exposed by
/// each AI plugin instead of reaching into this helper directly.
@MainActor
enum AIPluginGroup {
    static let tabGroup = NotchPluginTabGroup(
        id: "ai",
        title: "AI",
        iconSystemName: "sparkles",
        memberPluginIDs: ["claude", "codex", "devin"]
    )

    /// Synthetic plugin ID used for the merged AI tab (replaces "claude" / "codex" / "devin"
    /// at the shell layer).
    static let virtualTabID = tabGroup.id

    /// Picks AI plugins out of a mixed plugin list.
    static func aiPlugins(from plugins: [any NotchPlugin]) -> [any AIPluginRendering] {
        plugins.compactMap { $0 as? any AIPluginRendering }
    }

    /// All non-AI plugins in the list, preserving order.
    static func nonAIPlugins(from plugins: [any NotchPlugin]) -> [any NotchPlugin] {
        plugins.filter { ($0 as? any AIPluginRendering) == nil }
    }

    /// Aggregate `dockOrder` for the AI group — the smallest among member plugins.
    /// Used so the merged AI tab takes the position of the earliest-ordered AI plugin.
    static func dockOrder(of plugins: [any AIPluginRendering]) -> Int {
        plugins.map(\.dockOrder).min() ?? Int.max
    }
}
