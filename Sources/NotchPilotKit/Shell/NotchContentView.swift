import SwiftUI

public struct NotchContentView: View {
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let closeSpring = Animation.spring(response: 0.32, dampingFraction: 0.95, blendDuration: 0)
    private let closedCornerInsets = (top: CGFloat(6), bottom: CGFloat(14))
    private let openedCornerInsets = (top: CGFloat(19), bottom: CGFloat(24))
    private let hoverClosedExpansion = CGSize.zero

    @ObservedObject private var session: ScreenSessionModel
    @ObservedObject private var pluginManager: PluginManager
    @ObservedObject private var store = SettingsStore.shared

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
            isPrimaryScreen: session.descriptor.isPrimary,
            currentSneakPeek: session.currentSneakPeek
        )
        let layoutMetrics = NotchLayoutMetrics.resolve(session: session, plugins: plugins)
        let displaySize = visualDisplaySize(layoutMetrics.displaySize)
        let interactionSize = layoutMetrics.interactionSize
        let previewPlugin = pluginManager.previewPlugin(for: session.currentSneakPeek, context: context)

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .topLeading) {
                background

                if session.notchState == .open {
                    expandedBody(plugins: plugins, context: context)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if session.notchState == .previewClosed,
                          let previewPlugin {
                    previewClosedBody(previewPlugin: previewPlugin, context: context)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    idleBody
                        .transition(.opacity)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .clipShape(currentNotchShape, style: NotchRenderingStyle.edgeFillStyle)
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
    }

    @ViewBuilder
    private func previewClosedBody(previewPlugin: any NotchPlugin, context: NotchContext) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let preview = previewPlugin.preview(context: context) {
                previewBody(preview)
            } else {
                idleBody
            }
        }
    }

    private var background: some View {
        Color.black
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
        NotchExpandedLayout.safeHorizontalPadding
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
        let aiPlugins = AIPluginGroup.aiPlugins(from: plugins)
        let nonAIPlugins = AIPluginGroup.nonAIPlugins(from: plugins)
        let resolvedActiveID = AIPluginGroup.resolvedActivePluginID(session.activePluginID)
        let activePlugin = activePlugin(
            nonAIPlugins: nonAIPlugins,
            aiPluginsExist: !aiPlugins.isEmpty,
            resolvedActiveID: resolvedActiveID
        )
        let aiTabActive = resolvedActiveID == AIPluginGroup.virtualTabID

        return VStack(alignment: .leading, spacing: 12) {
            headerRow(
                nonAIPlugins: nonAIPlugins,
                aiPlugins: aiPlugins,
                activePluginID: activePlugin?.id,
                aiTabActive: aiTabActive
            )

            if aiTabActive, !aiPlugins.isEmpty {
                aiMergedViewport(aiPlugins: aiPlugins, context: context)
            } else if let activePlugin {
                pluginContentViewport(activePlugin, context: context)
            } else {
                NotchPilotHUDPanel(cornerRadius: 28) {
                    Text(AppStrings.text(.noPluginsEnabled, language: store.interfaceLanguage))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(24)
                }
                .padding(.horizontal, expandedSafeHorizontalPadding)
            }
        }
        .padding(.top, NotchExpandedLayout.topPadding)
        .padding(.bottom, NotchExpandedLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pluginContentViewport(
        _ plugin: any NotchPlugin,
        context: NotchContext
    ) -> some View {
        plugin.contentView(context: context)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .padding(.horizontal, expandedSafeHorizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: NotchExpandedLayout.pluginViewportHeight(forDisplayHeight: context.notchGeometry.expandedSize.height),
                maxHeight: NotchExpandedLayout.pluginViewportHeight(forDisplayHeight: context.notchGeometry.expandedSize.height),
                alignment: .topLeading
            )
            .clipped()
    }

    private func aiMergedViewport(
        aiPlugins: [any AIPluginRendering],
        context: NotchContext
    ) -> some View {
        AIPluginMergedExpandedView(plugins: aiPlugins)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .padding(.horizontal, expandedSafeHorizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: NotchExpandedLayout.pluginViewportHeight(forDisplayHeight: context.notchGeometry.expandedSize.height),
                maxHeight: NotchExpandedLayout.pluginViewportHeight(forDisplayHeight: context.notchGeometry.expandedSize.height),
                alignment: .topLeading
            )
            .clipped()
    }

    private func headerRow(
        nonAIPlugins: [any NotchPlugin],
        aiPlugins: [any AIPluginRendering],
        activePluginID: String?,
        aiTabActive: Bool
    ) -> some View {
        let aiDockOrder = AIPluginGroup.dockOrder(of: aiPlugins)
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(headerTabs(nonAIPlugins: nonAIPlugins, aiPlugins: aiPlugins, aiDockOrder: aiDockOrder), id: \.id) { tab in
                    switch tab {
                    case .plugin(let plugin):
                        pluginTabButton(
                            plugin: plugin,
                            isActive: activePluginID == plugin.id
                        )
                    case .ai:
                        aiTabButton(isActive: aiTabActive)
                    }
                }
            }

            Spacer(minLength: 0)

            shellSettingsButton
        }
        .frame(height: NotchExpandedLayout.headerHeight)
        .padding(.horizontal, expandedSafeHorizontalPadding)
    }

    @MainActor
    private enum HeaderTab {
        case plugin(any NotchPlugin)
        case ai

        var id: String {
            switch self {
            case .plugin(let p): return p.id
            case .ai: return AIPluginGroup.virtualTabID
            }
        }
    }

    private func headerTabs(
        nonAIPlugins: [any NotchPlugin],
        aiPlugins: [any AIPluginRendering],
        aiDockOrder: Int
    ) -> [HeaderTab] {
        var tabs: [(order: Int, tab: HeaderTab)] = nonAIPlugins.map { ($0.dockOrder, .plugin($0)) }
        if !aiPlugins.isEmpty {
            tabs.append((aiDockOrder, .ai))
        }
        return tabs
            .sorted { $0.order < $1.order }
            .map(\.tab)
    }

    private func aiTabButton(isActive: Bool) -> some View {
        Button {
            session.activePluginID = AIPluginGroup.virtualTabID
        } label: {
            ZStack {
                Image(systemName: "sparkles")
                    .font(.system(size: NotchExpandedLayout.pluginTabIconSize - 2, weight: .bold))
                    .foregroundStyle(isActive ? NotchPilotTheme.islandTextPrimary : NotchPilotTheme.claude)
            }
            .frame(
                width: NotchExpandedLayout.pluginTabSize.width,
                height: NotchExpandedLayout.pluginTabSize.height
            )
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        NotchPilotTheme.claude.opacity(0.2),
                                        NotchPilotTheme.claude.opacity(0.08),
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
                        isActive ? NotchPilotTheme.claude.opacity(0.18) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI")
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
                    NotchPilotBrandIcon(glyph: glyph, size: NotchExpandedLayout.pluginTabIconSize)
                } else {
                    Image(systemName: plugin.iconSystemName)
                        .font(.system(size: NotchExpandedLayout.pluginTabIconSize - 2, weight: .bold))
                        .foregroundStyle(isActive ? NotchPilotTheme.islandTextPrimary : plugin.accentColor)
                }
            }
            .frame(
                width: NotchExpandedLayout.pluginTabSize.width,
                height: NotchExpandedLayout.pluginTabSize.height
            )
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
        .accessibilityLabel(pluginTabAccessibilityLabel(plugin))
    }

    private func pluginTabAccessibilityLabel(_ plugin: any NotchPlugin) -> String {
        switch plugin.id {
        case SettingsPluginID.media.rawValue:
            return AppStrings.text(.media, language: store.interfaceLanguage)
        case SettingsPluginID.systemMonitor.rawValue:
            return AppStrings.text(.system, language: store.interfaceLanguage)
        case SettingsPluginID.notifications.rawValue:
            return AppStrings.text(.notifications, language: store.interfaceLanguage)
        default:
            return plugin.title
        }
    }

    private var shellSettingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: NotchExpandedLayout.settingsIconSize, weight: .bold))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .frame(
                    width: NotchExpandedLayout.settingsButtonSize,
                    height: NotchExpandedLayout.settingsButtonSize
                )
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
        .accessibilityLabel(AppStrings.text(.openSettings, language: store.interfaceLanguage))
    }

    private func activePlugin(
        nonAIPlugins: [any NotchPlugin],
        aiPluginsExist: Bool,
        resolvedActiveID: String?
    ) -> (any NotchPlugin)? {
        // AI virtual tab is handled separately by `aiMergedViewport`; from this method's
        // perspective, the AI tab has no concrete plugin instance.
        if resolvedActiveID == AIPluginGroup.virtualTabID {
            return nil
        }

        if let activeID = resolvedActiveID,
           let plugin = nonAIPlugins.first(where: { $0.id == activeID }) {
            return plugin
        }

        // Fallback: pick the first non-AI plugin, or the AI virtual tab if there are no
        // non-AI plugins available.
        if let first = nonAIPlugins.first {
            session.activePluginID = first.id
            return first
        }
        if aiPluginsExist {
            session.activePluginID = AIPluginGroup.virtualTabID
        }
        return nil
    }
}
