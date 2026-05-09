import AppKit
import KeyboardShortcuts

/// Centralized registry of user-customizable keyboard shortcuts used by NotchPilot.
public extension KeyboardShortcuts.Name {
    /// Toggles `SettingsStore.activitySneakPreviewsHidden` (a.k.a. "Hide all previews").
    static let toggleHideAllPreviews = Self(
        "toggleHideAllPreviews",
        default: .init(.s, modifiers: [.command, .shift])
    )
}
