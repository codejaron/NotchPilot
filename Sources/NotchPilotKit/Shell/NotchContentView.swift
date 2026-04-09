import SwiftUI

public struct NotchContentView: View {
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let closeSpring = Animation.spring(response: 0.32, dampingFraction: 0.95, blendDuration: 0)
    private let closedCornerInsets = (top: CGFloat(6), bottom: CGFloat(14))
    private let openedCornerInsets = (top: CGFloat(19), bottom: CGFloat(24))

    @ObservedObject private var session: ScreenSessionModel
    @ObservedObject private var pluginManager: PluginManager

    public init(session: ScreenSessionModel, pluginManager: PluginManager) {
        self.session = session
        self.pluginManager = pluginManager
    }

    public var body: some View {
        let plugins = pluginManager.enabledPlugins
        let context = NotchContext(
            screenID: session.id,
            notchState: session.notchState,
            notchGeometry: session.geometry,
            isPrimaryScreen: session.descriptor.isPrimary
        )
        let layoutMetrics = NotchLayoutMetrics.resolve(session: session, plugins: plugins)
        let displaySize = layoutMetrics.displaySize
        let interactionSize = layoutMetrics.interactionSize
        let previewPlugin = pluginManager.previewPlugin(for: session.currentSneakPeek, context: context)
        let preview = previewPlugin?.preview(context: context)

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
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
            }
            .frame(width: interactionSize.width, height: interactionSize.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .frame(width: session.windowSize.width, height: session.windowSize.height, alignment: .top)
        .animation(currentAnimation, value: session.notchState)
        .animation(animationSpring, value: session.currentSneakPeek?.id)
        .animation(animationSpring, value: previewPlugin?.id)
        .animation(animationSpring, value: displaySize)
    }

    private var background: some View {
        currentNotchShape
            .fill(Color.black.opacity(0.92))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.92))
                    .frame(height: 1)
                    .padding(.horizontal, currentTopCornerRadius)
            }
            .overlay(
                currentNotchShape
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 18, y: 10)
    }

    private var currentAnimation: Animation {
        session.notchState == .open ? animationSpring : closeSpring
    }

    private var currentTopCornerRadius: CGFloat {
        session.notchState == .open ? openedCornerInsets.top : closedCornerInsets.top
    }

    private var currentNotchShape: NotchShape {
        if session.notchState == .open {
            return NotchShape(topCornerRadius: openedCornerInsets.top, bottomCornerRadius: openedCornerInsets.bottom)
        }

        return NotchShape(topCornerRadius: closedCornerInsets.top, bottomCornerRadius: closedCornerInsets.bottom)
    }

    private var idleBody: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewBody(_ preview: NotchPluginPreview) -> some View {
        preview.view
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func expandedBody(plugins: [any NotchPlugin], context: NotchContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            dockRow(plugins: plugins)

            if let activePlugin = activePlugin(from: plugins) {
                activePlugin.contentView(context: context)
            } else {
                Text("No plugins enabled.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dockRow(plugins: [any NotchPlugin]) -> some View {
        HStack(spacing: 10) {
            ForEach(plugins, id: \.id) { plugin in
                Button {
                    session.activePluginID = plugin.id
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: plugin.iconSystemName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.96))
                            .frame(width: 42, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        session.activePluginID == plugin.id
                                            ? plugin.accentColor.opacity(0.28)
                                            : Color.white.opacity(0.07)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        session.activePluginID == plugin.id
                                            ? plugin.accentColor.opacity(0.45)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )

                        Text(plugin.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                session.activePluginID == plugin.id
                                    ? .white.opacity(0.96)
                                    : .white.opacity(0.52)
                            )
                    }
                    .frame(width: 58)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
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
