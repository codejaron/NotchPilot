import Foundation

/// Helpers for treating multiple AI plugins (Claude, Codex, Devin) as a single group
/// in the notch shell. Used by `NotchContentView` to render one virtual "AI" tab
/// for all AI plugins, and to map legacy per-host plugin IDs to the unified tab ID.
@MainActor
enum AIPluginGroup {
    /// Synthetic plugin ID used for the merged AI tab (replaces "claude" / "codex" / "devin"
    /// at the shell layer).
    static let virtualTabID = "ai"

    /// Plugin IDs that belong to the AI group. When any of these appears in
    /// persisted state (e.g. `activePluginID`), it should be mapped to `virtualTabID`.
    static let memberPluginIDs: Set<String> = ["claude", "codex", "devin"]

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
