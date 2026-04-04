import SwiftUI

public struct NotchContentView: View {
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let closeSpring = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    private let closedCornerInsets = (top: CGFloat(6), bottom: CGFloat(14))
    private let openedCornerInsets = (top: CGFloat(19), bottom: CGFloat(24))
    private let closedInteractionHorizontalPadding: CGFloat = 30
    private let closedInteractionBottomPadding: CGFloat = 10
    @State private var gestureProgress: CGFloat = 0

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
        let displaySize = preferredDisplaySize(plugins: plugins, context: context)
        let interactionSize = preferredInteractionSize(for: displaySize)

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                ZStack(alignment: .topLeading) {
                    background

                    if session.notchState == .open {
                        expandedBody(plugins: plugins, context: context)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    } else if session.showsSneakPeekOverlay,
                              let currentSneakPeek = session.currentSneakPeek,
                              let plugin = pluginManager.plugin(id: currentSneakPeek.pluginID),
                              let view = plugin.sneakPeekView(context: context) {
                        sneakPeekBody(plugins: plugins, context: context, view: view)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        compactBody(plugins: plugins, context: context)
                            .transition(.opacity)
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .scaleEffect(x: 1, y: 1 + (gestureProgress * 0.01), anchor: .top)
            }
            .frame(width: interactionSize.width, height: interactionSize.height, alignment: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                session.setHover(hovering, fallbackPluginID: plugins.first?.id)
            }
            .onTapGesture {
                session.toggleOpen(defaultPluginID: plugins.first?.id)
            }
            .gesture(dragGesture(defaultPluginID: plugins.first?.id))
        }
        .frame(width: session.windowSize.width, height: session.windowSize.height, alignment: .top)
        .animation(currentAnimation, value: session.notchState)
        .animation(animationSpring, value: session.currentSneakPeek?.id)
        .animation(animationSpring, value: displaySize)
        .animation(.smooth, value: gestureProgress)
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

    private func compactBody(plugins: [any NotchPlugin], context: NotchContext) -> some View {
        HStack(spacing: 12) {
            ForEach(plugins, id: \.id) { plugin in
                if let compact = plugin.compactView(context: context) {
                    compact
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func sneakPeekBody(plugins: [any NotchPlugin], context: NotchContext, view: AnyView) -> some View {
        VStack(spacing: 8) {
            compactBody(plugins: plugins, context: context)
                .frame(height: max(context.notchGeometry.compactSize.height, 34), alignment: .top)

            view
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func expandedBody(plugins: [any NotchPlugin], context: NotchContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(plugins, id: \.id) { plugin in
                    Button {
                        session.activePluginID = plugin.id
                    } label: {
                        Label(plugin.name, systemImage: plugin.iconSystemName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(session.activePluginID == plugin.id ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                Spacer()
            }

            if let activePlugin = activePlugin(from: plugins) {
                activePlugin.expandedView(context: context)
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

    private func activePlugin(from plugins: [any NotchPlugin]) -> (any NotchPlugin)? {
        if let activeID = session.activePluginID, let plugin = plugins.first(where: { $0.id == activeID }) {
            return plugin
        }

        let first = plugins.first
        session.activePluginID = first?.id
        return first
    }

    private func dragGesture(defaultPluginID: String?) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.height

                if session.notchState == .closed, translation > 0 {
                    gestureProgress = min(translation / 80, 1)
                } else if session.notchState == .open, translation < 0 {
                    gestureProgress = max(translation / 80, -1)
                } else {
                    gestureProgress = 0
                }
            }
            .onEnded { value in
                defer {
                    withAnimation(animationSpring) {
                        gestureProgress = 0
                    }
                }

                let translation = value.translation.height
                if session.notchState == .closed, translation > 40 {
                    session.toggleOpen(defaultPluginID: defaultPluginID)
                } else if session.notchState == .open, translation < -40 {
                    session.close()
                }
            }
    }

    private func preferredDisplaySize(plugins: [any NotchPlugin], context: NotchContext) -> CGSize {
        switch session.notchState {
        case .open:
            return session.geometry.expandedSize
        case .closed:
            let compactWidth = max(
                session.geometry.compactSize.width,
                plugins.compactMap { $0.compactWidth(context: context) }.max() ?? 0
            )
            return CGSize(width: compactWidth, height: session.geometry.compactSize.height)
        case .sneakPeek:
            let compactWidth = max(
                session.geometry.compactSize.width,
                plugins.compactMap { $0.compactWidth(context: context) }.max() ?? 0
            )
            let sneakPeekWidth = max(
                compactWidth,
                plugins.compactMap { $0.sneakPeekWidth(context: context) }.max() ?? 0
            )
            return CGSize(width: sneakPeekWidth, height: max(session.geometry.compactSize.height + 86, 120))
        }
    }

    private func preferredInteractionSize(for displaySize: CGSize) -> CGSize {
        guard session.notchState != .open else {
            return displaySize
        }

        return CGSize(
            width: displaySize.width + (closedInteractionHorizontalPadding * 2),
            height: displaySize.height + closedInteractionBottomPadding
        )
    }
}
