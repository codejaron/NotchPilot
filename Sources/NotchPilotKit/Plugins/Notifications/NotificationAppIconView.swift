import AppKit
import SwiftUI

@MainActor
private final class NotificationAppIconCache {
    static let shared = NotificationAppIconCache()

    private var icons: [String: NSImage?] = [:]

    func icon(for bundleIdentifier: String) -> NSImage? {
        if let cached = icons[bundleIdentifier] {
            return cached
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            icons[bundleIdentifier] = .some(nil)
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleIdentifier] = icon
        return icon
    }
}

struct NotificationAppIconView: View {
    let bundleIdentifier: String
    let accentColor: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let image = NotificationAppIconCache.shared.icon(for: bundleIdentifier) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(size * 0.08)
                    .background {
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            } else {
                NotchPilotIconTile(
                    systemName: "bell.badge.fill",
                    accent: accentColor,
                    size: size,
                    isActive: true
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
