import SwiftUI

public struct NotchContentView: View {
    private let previewRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let closeSpring = Animation.spring(response: 0.32, dampingFraction: 0.95, blendDuration: 0)
    private let closedCornerInsets = (top: CGFloat(6), bottom: CGFloat(14))
    private let openedCornerInsets = (top: CGFloat(19), bottom: CGFloat(24))
    private let hoverClosedExpansion = CGSize(width: 22, height: 6)

    @ObservedObject private var session: ScreenSessionModel
    @ObservedObject private var pluginManager: PluginManager
    @State private var previewRefreshTick = Date()

    public init(session: ScreenSessionModel, pluginManager: PluginManager) {
        self.session = session
        self.pluginManager = pluginManager
    }

    public var body: some View {
        let _ = previewRefreshTick
        let plugins = pluginManager.enabledPlugins
        let context = NotchContext(
            screenID: session.id,
            notchState: session.notchState,
            notchGeometry: session.geometry,
            isPrimaryScreen: session.descriptor.isPrimary
        )
        let layoutMetrics = NotchLayoutMetrics.resolve(session: session, plugins: plugins)
        let displaySize = visualDisplaySize(layoutMetrics.displaySize)
        let interactionSize = layoutMetrics.interactionSize
        let previewPlugin = pluginManager.previewPlugin(for: session.currentSneakPeek, context: context)
        let preview = previewPlugin?.preview(context: context)

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .topLeading) {
                background

                if session.notchState == .open {
                    expandedBody(plugins: plugins, context: context)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if session.notchState == .previewClosed,
                          let preview {
                    previewBody(preview)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    idleBody
                        .transition(.opacity)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .clipShape(currentNotchShape)
            .frame(width: interactionSize.width, height: interactionSize.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .frame(width: session.windowSize.width, height: session.windowSize.height, alignment: .top)
        .animation(currentAnimation, value: session.notchState)
        .animation(animationSpring, value: session.currentSneakPeek?.id)
        .animation(animationSpring, value: previewPlugin?.id)
        .animation(animationSpring, value: displaySize)
        .animation(animationSpring, value: session.hoverState)
        .sensoryFeedback(.alignment, trigger: session.hoverFeedbackTrigger)
        .onReceive(previewRefreshTimer) { date in
            guard session.notchState == .previewClosed else {
                return
            }
            previewRefreshTick = date
        }
    }

    private var background: some View {
        currentNotchShape
            .fill(Color.black)
    }

    private var currentAnimation: Animation {
        session.notchState == .open ? animationSpring : closeSpring
    }

    private var currentNotchShape: NotchShape {
        if session.notchState == .open {
            return NotchShape(topCornerRadius: openedCornerInsets.top, bottomCornerRadius: openedCornerInsets.bottom)
        }

        return NotchShape(topCornerRadius: closedCornerInsets.top, bottomCornerRadius: closedCornerInsets.bottom)
    }

    private var expandedSafeHorizontalPadding: CGFloat {
        openedCornerInsets.top + 8
    }

    private func visualDisplaySize(_ baseSize: CGSize) -> CGSize {
        guard session.hoverState, session.notchState != .open else {
            return baseSize
        }

        return CGSize(
            width: baseSize.width + hoverClosedExpansion.width,
            height: baseSize.height + hoverClosedExpansion.height
        )
    }

    private var idleBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(.white.opacity(0.06))
                .frame(width: 62, height: 3)
                .offset(y: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewBody(_ preview: NotchPluginPreview) -> some View {
        preview.view
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func expandedBody(plugins: [any NotchPlugin], context: NotchContext) -> some View {
        let activePlugin = activePlugin(from: plugins)

        return VStack(alignment: .leading, spacing: 12) {
            headerRow(plugins: plugins, activePlugin: activePlugin)

            if let activePlugin {
                activePlugin.contentView(context: context)
                    .padding(.horizontal, expandedSafeHorizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                NotchPilotHUDPanel(cornerRadius: 28) {
                    Text("No plugins enabled.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(24)
                }
                .padding(.horizontal, expandedSafeHorizontalPadding)
            }
        }
        .padding(.top, 7)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func headerRow(
        plugins: [any NotchPlugin],
        activePlugin: (any NotchPlugin)?
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(plugins, id: \.id) { plugin in
                    pluginTabButton(
                        plugin: plugin,
                        isActive: activePlugin?.id == plugin.id
                    )
                }
            }

            Spacer(minLength: 0)

            shellSettingsButton
        }
        .frame(height: 32)
        .padding(.horizontal, expandedSafeHorizontalPadding)
    }

    private func pluginTabButton(
        plugin: any NotchPlugin,
        isActive: Bool
    ) -> some View {
        Button {
            session.activePluginID = plugin.id
        } label: {
            ZStack {
                if let glyph = NotchPilotBrandGlyph(pluginID: plugin.id) {
                    NotchPilotBrandIcon(glyph: glyph, size: 16)
                } else {
                    Image(systemName: plugin.iconSystemName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isActive ? NotchPilotTheme.islandTextPrimary : plugin.accentColor)
                }
            }
            .frame(width: 42, height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        plugin.accentColor.opacity(plugin.id == "claude" ? 0.2 : 0.24),
                                        plugin.accentColor.opacity(0.08),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.clear)
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? plugin.accentColor.opacity(0.18) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plugin.title)
    }

    private var shellSettingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .bold))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
            )
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Settings")
    }

    private func activePlugin(from plugins: [any NotchPlugin]) -> (any NotchPlugin)? {
        if let activeID = session.activePluginID, let plugin = plugins.first(where: { $0.id == activeID }) {
            return plugin
        }

        let first = plugins.first
        session.activePluginID = first?.id
        return first
    }
}
