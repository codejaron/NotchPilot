import AppKit
import SwiftUI

enum NotchPilotTheme {
    static let mediaPlayback = Color(red: 0.24, green: 0.84, blue: 0.47)
    static let claude = Color(red: 0.80, green: 0.51, blue: 0.38)
    static let codex = Color(red: 0.37, green: 0.53, blue: 0.86)
    static let systemMonitor = Color(red: 0.36, green: 0.82, blue: 1.0)
    static let success = Color(red: 0.36, green: 0.84, blue: 0.54)
    static let warning = Color(red: 1.0, green: 0.67, blue: 0.18)
    static let danger = Color(red: 1.0, green: 0.41, blue: 0.41)

    static let islandOuterTop = Color(red: 0.045, green: 0.028, blue: 0.02)
    static let islandOuterBottom = Color.black
    static let islandInnerTop = Color.white.opacity(0.032)
    static let islandInnerBottom = Color.white.opacity(0.008)
    static let islandHairline = Color.white.opacity(0.09)
    static let islandDivider = Color.white.opacity(0.08)
    static let islandTextPrimary = Color.white.opacity(0.97)
    static let islandTextSecondary = Color.white.opacity(0.72)
    static let islandTextMuted = Color.white.opacity(0.4)

    static func brand(for host: AIHost) -> Color {
        host == .claude ? claude : codex
    }

    static func brand(for plugin: SettingsPluginID) -> Color {
        switch plugin {
        case .media:
            return mediaPlayback
        case .claude:
            return claude
        case .codex:
            return codex
        case .systemMonitor:
            return systemMonitor
        }
    }

    static func brand(for pluginID: String?) -> Color {
        if pluginID == "media-playback" {
            return mediaPlayback
        }
        if pluginID == "system-monitor" {
            return systemMonitor
        }
        return pluginID == "claude" ? claude : codex
    }

    static func settingsCanvas(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(nsColor: .windowBackgroundColor),
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                ]
                : [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.9, green: 0.93, blue: 0.97),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func settingsSidebarFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.15)
            : Color.white.opacity(0.8)
    }

    static func settingsPanelFill(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.17, green: 0.18, blue: 0.22),
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                ]
                : [
                    Color.white.opacity(0.95),
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func settingsPanelStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.7)
    }

    static func settingsShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .black.opacity(0.28)
            : Color(red: 0.3, green: 0.38, blue: 0.49).opacity(0.12)
    }

    static func settingsTextSecondary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.62) : .secondary
    }

    static func settingsWindowBackground(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static func settingsGroupFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor)
            : Color(nsColor: .textBackgroundColor)
    }

    static func settingsGroupStroke(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: .separatorColor)
            .opacity(colorScheme == .dark ? 0.55 : 0.45)
    }

    static func settingsDivider(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: .separatorColor)
            .opacity(colorScheme == .dark ? 0.55 : 0.35)
    }

    static func settingsSelectionFill(accent: Color, colorScheme: ColorScheme) -> Color {
        accent.opacity(colorScheme == .dark ? 0.22 : 0.16)
    }

    static func settingsSelectionStroke(accent: Color, colorScheme: ColorScheme) -> Color {
        accent.opacity(colorScheme == .dark ? 0.42 : 0.26)
    }

    static func statusFill(for color: Color) -> Color {
        color.opacity(0.18)
    }

}

enum NotchPilotBrandGlyph: String {
    case claude
    case codex

    init?(pluginID: String?) {
        switch pluginID {
        case "claude":
            self = .claude
        case "codex":
            self = .codex
        default:
            return nil
        }
    }

    init?(host: AIHost) {
        self = host == .claude ? .claude : .codex
    }

    init?(systemName: String) {
        switch systemName {
        case "sparkles":
            self = .claude
        case "terminal":
            self = .codex
        default:
            return nil
        }
    }

    var resourceName: String {
        switch self {
        case .claude:
            return "claude-color"
        case .codex:
            return "codex-color"
        }
    }

    var fallbackSystemName: String {
        switch self {
        case .claude:
            return "sparkles"
        case .codex:
            return "terminal"
        }
    }
}

private enum NotchPilotBrandImageStore {
    @MainActor
    static func image(for glyph: NotchPilotBrandGlyph) -> NSImage? {
        if let cached = cache[glyph] {
            return cached
        }

        let bundledURL = Bundle.module.url(
            forResource: glyph.resourceName,
            withExtension: "svg",
            subdirectory: "Icons"
        ) ?? Bundle.module.url(
            forResource: glyph.resourceName,
            withExtension: "svg"
        )

        guard let bundledURL,
              let image = NSImage(contentsOf: bundledURL) else {
            return nil
        }

        cache[glyph] = image
        return image
    }

    @MainActor
    private static var cache: [NotchPilotBrandGlyph: NSImage] = [:]
}

struct NotchPilotBrandIcon: View {
    let glyph: NotchPilotBrandGlyph
    let size: CGFloat

    init(glyph: NotchPilotBrandGlyph, size: CGFloat) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        Group {
            if let image = NotchPilotBrandImageStore.image(for: glyph) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: glyph.fallbackSystemName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(glyph == .claude ? NotchPilotTheme.claude : .white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct NotchPilotHUDPanel<Content: View>: View {
    let accent: Color?
    let cornerRadius: CGFloat
    let content: Content

    init(
        accent: Color? = nil,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                NotchPilotTheme.islandOuterTop.opacity(0.96),
                                NotchPilotTheme.islandOuterBottom.opacity(0.98),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        NotchPilotTheme.islandInnerTop,
                                        NotchPilotTheme.islandInnerBottom,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(1)
                    }
                    .overlay {
                        if let accent {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(accent.opacity(0.14), lineWidth: 1)
                                .padding(1)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(NotchPilotTheme.islandHairline, lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.12),
                                        .white.opacity(0.01),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .blur(radius: 0.25)
                    }
                    .shadow(color: .black.opacity(0.36), radius: 28, y: 18)
            }
    }
}

struct NotchPilotToolPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color?
    let cornerRadius: CGFloat
    let content: Content

    init(
        accent: Color? = nil,
        cornerRadius: CGFloat = 22,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(NotchPilotTheme.settingsPanelFill(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(NotchPilotTheme.settingsPanelStroke(for: colorScheme), lineWidth: 1)
                    }
                    .overlay {
                        if let accent {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.18 : 0.1), lineWidth: 1)
                                .padding(1)
                        }
                    }
                    .shadow(color: NotchPilotTheme.settingsShadow(for: colorScheme), radius: 20, y: 10)
            }
    }
}

struct NotchPilotStatusBadge: View {
    let text: String
    let color: Color
    let foreground: Color?

    init(text: String, color: Color, foreground: Color? = nil) {
        self.text = text
        self.color = color
        self.foreground = foreground
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(NotchPilotTheme.statusFill(for: color))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.2), lineWidth: 1)
            }
            .foregroundStyle(foreground ?? color)
    }
}

struct NotchPilotIconTile: View {
    let systemName: String
    let accent: Color
    let size: CGFloat
    let isActive: Bool

    init(systemName: String, accent: Color, size: CGFloat = 36, isActive: Bool = false) {
        self.systemName = systemName
        self.accent = accent
        self.size = size
        self.isActive = isActive
    }

    var body: some View {
        Group {
            if let glyph = NotchPilotBrandGlyph(systemName: systemName) {
                NotchPilotBrandIcon(glyph: glyph, size: size * 0.54)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(isActive ? Color.white : accent)
            }
        }
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isActive
                                ? [Color.white.opacity(0.1), accent.opacity(0.16)]
                                : [accent.opacity(0.16), accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.white.opacity(0.24) : accent.opacity(0.18),
                        lineWidth: 1
                    )
            }
    }
}
