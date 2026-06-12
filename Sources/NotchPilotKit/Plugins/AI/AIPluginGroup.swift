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

    /// Plugin IDs that belong to the AI group. When any of these appears in
    /// persisted state (e.g. `activePluginID`), it should be mapped to `virtualTabID`.
    static let memberPluginIDs = tabGroup.memberPluginIDs

    /// Picks AI plugins out of a mixed plugin list.
    static func aiPlugins(from plugins: [any NotchPlugin]) -> [any AIPluginRendering] {
        plugins.compactMap { $0 as? any AIPluginRendering }
    }

    /// All non-AI plugins in the list, preserving order.
    static func nonAIPlugins(from plugins: [any NotchPlugin]) -> [any NotchPlugin] {
        plugins.filter { ($0 as? any AIPluginRendering) == nil }
    }

    /// Maps legacy per-host plugin IDs (e.g. "claude" / "codex" / "devin") to the
    /// unified `virtualTabID`. Other IDs pass through unchanged.
    static func resolvedActivePluginID(_ rawID: String?) -> String? {
        guard let rawID else { return nil }
        return memberPluginIDs.contains(rawID) ? virtualTabID : rawID
    }

    /// Aggregate `dockOrder` for the AI group — the smallest among member plugins.
    /// Used so the merged AI tab takes the position of the earliest-ordered AI plugin.
    static func dockOrder(of plugins: [any AIPluginRendering]) -> Int {
        plugins.map(\.dockOrder).min() ?? Int.max
    }
}
