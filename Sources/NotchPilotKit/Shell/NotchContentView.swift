import SwiftUI
import UniformTypeIdentifiers

public struct NotchContentView: View {
    private static let expandedContentTransition: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity),
        removal: .scale(scale: 0.55, anchor: .top).combined(with: .opacity)
    )
    private let closedCornerInsets = (top: CGFloat(6), bottom: CGFloat(14))
    private let openedCornerInsets = (top: CGFloat(19), bottom: CGFloat(24))
    private let hoverClosedExpansion = CGSize.zero

    @ObservedObject private var session: ScreenSessionModel
    @ObservedObject private var pluginManager: PluginManager
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @State private var globalDropResultClearTask: Task<Void, Never>?

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
        let dropStripHeight = NotchExpandedLayout.dropStripHeight(for: session.globalDropStripState)
        let contentHeight = max(0, displaySize.height - dropStripHeight)
        let interactionSize = layoutMetrics.interactionSize
        let previewPlugin = pluginManager.previewPlugin(for: session.currentSneakPeek, context: context)

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                chromeShadow(displaySize: displaySize)

                chromeSurface(
                    displaySize: displaySize,
                    contentHeight: contentHeight,
                    plugins: plugins,
                    context: context,
                    previewPlugin: previewPlugin
                )
            }
            .frame(width: interactionSize.width, height: interactionSize.height, alignment: .top)
            .contentShape(Rectangle())
            .onDrop(
                of: [.fileURL],
                delegate: NotchGlobalFileDropDelegate(
                    handler: globalDropHandler,
                    onStateChange: handleGlobalDropStateChange,
                    onDropCompleted: handleGlobalDropCompleted
                )
            )
        }
        .frame(width: session.windowSize.width, height: session.windowSize.height, alignment: .top)
        .animation(ScreenSessionModel.sneakAnimation, value: previewPlugin?.id)
        .animation(ScreenSessionModel.sneakAnimation, value: session.globalDropStripState)
        .sensoryFeedback(.alignment, trigger: session.hoverFeedbackTrigger)
    }

    private func chromeShadow(displaySize: CGSize) -> some View {
        currentNotchShape
            .fill(Color.black, style: NotchRenderingStyle.edgeFillStyle)
            .frame(width: displaySize.width, height: displaySize.height)
            .opacity(isOpen ? 1 : 0)
            .shadow(
                color: .black.opacity(isOpen ? NotchChromeShadow.ambientLayer.opacity : 0),
                radius: isOpen ? NotchChromeShadow.ambientLayer.radius : 0,
                x: NotchChromeShadow.ambientLayer.x,
                y: isOpen ? NotchChromeShadow.ambientLayer.y : 0
            )
            .shadow(
                color: .black.opacity(isOpen ? NotchChromeShadow.depthLayer.opacity : 0),
                radius: isOpen ? NotchChromeShadow.depthLayer.radius : 0,
                x: NotchChromeShadow.depthLayer.x,
                y: isOpen ? NotchChromeShadow.depthLayer.y : 0
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func chromeSurface(
        displaySize: CGSize,
        contentHeight: CGFloat,
        plugins: [any NotchPlugin],
        context: NotchContext,
        previewPlugin: (any NotchPlugin)?
    ) -> some View {
        ZStack(alignment: .topLeading) {
            background

            ZStack(alignment: .topLeading) {
                if session.notchState == .open {
                    expandedBody(plugins: plugins, context: context)
                        .transition(Self.expandedContentTransition)
                } else if session.notchState == .previewClosed,
                          let previewPlugin {
                    previewClosedBody(previewPlugin: previewPlugin, context: context)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    idleBody
                        .transition(.opacity)
                }
            }
            .frame(width: displaySize.width, height: contentHeight, alignment: .topLeading)

            if session.globalDropStripState.isVisible {
                globalDropStripView
                    .frame(width: displaySize.width, height: NotchExpandedLayout.globalDropStripHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(currentNotchShape, style: NotchRenderingStyle.edgeFillStyle)
        .compositingGroup()
    }

    @ViewBuilder
    private func previewClosedBody(previewPlugin: any NotchPlugin, context: NotchContext) -> some View {
        if let preview = previewPlugin.preview(context: context) {
            previewBody(preview)
        } else {
            idleBody
        }
    }

    private var isOpen: Bool {
        session.notchState == .open
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.black, Color.black.opacity(0.96)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var globalDropHandler: NotchGlobalDropHandler {
        NotchGlobalDropHandler(
            notesPlugin: {
                pluginManager.registeredPlugin(id: SettingsPluginID.notes.rawValue) as? NotesPlugin
            },
            selectNotes: {
                session.activePluginID = SettingsPluginID.notes.rawValue
            }
        )
    }

    private var globalDropStripView: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(dropStripTint)

            Text(session.globalDropStripState.message(language: language))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let accessoryText = session.globalDropStripState.accessoryText(language: language) {
                Text(accessoryText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, expandedSafeHorizontalPadding)
        .frame(height: NotchExpandedLayout.globalDropStripHeight)
        .background(Color.white.opacity(0.045))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NotchPilotTheme.islandDivider)
                .frame(height: 1)
        }
    }

    private var dropStripTint: Color {
        switch session.globalDropStripState {
        case .hovering, .accepted:
            return NotchPilotTheme.notes
        case .failed, .rejected:
            return NotchPilotTheme.warning
        case .inactive:
            return NotchPilotTheme.islandTextMuted
        }
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
        let tabs = NotchPluginTabCollection(plugins: plugins)
        let resolvedActiveID = tabs.resolvedTabID(session.activePluginID)
        let activeSelection = activeSelection(in: tabs, resolvedActiveID: resolvedActiveID)

        return VStack(alignment: .leading, spacing: 12) {
            headerRow(
                tabs: tabs,
                activeSelection: activeSelection,
                context: context
            )

            switch activeSelection {
            case .group(let group):
                groupContentViewport(group, context: context)
            case .plugin(let activePlugin):
                pluginContentViewport(activePlugin, context: context)
            case .none:
                NotchPilotHUDPanel(cornerRadius: 28) {
                    Text(AppStrings.text(.noPluginsEnabled, language: language))
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

    private func groupContentViewport(
        _ group: NotchPluginTabCollection.Group,
        context: NotchContext
    ) -> some View {
        (group.contentView(context: context) ?? AnyView(EmptyView()))
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
        tabs: NotchPluginTabCollection,
        activeSelection: ActiveTabSelection,
        context: NotchContext
    ) -> some View {
        return HStack(spacing: 8) {
            let activeTabID = activeSelection.id
            HStack(spacing: 6) {
                ForEach(headerTabs(tabs: tabs), id: \.id) { tab in
                    switch tab {
                    case .plugin(let plugin):
                        pluginTabButton(
                            plugin: plugin,
                            isActive: activeTabID == plugin.id
                        )
                    case .group(let group):
                        groupTabButton(
                            group: group,
                            isActive: activeTabID == group.id
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            if let accessory = headerAccessory(for: activeSelection, context: context) {
                accessory
                    .layoutPriority(1)
            }

            shellSettingsButton
        }
        .frame(height: NotchExpandedLayout.headerHeight)
        .padding(.horizontal, expandedSafeHorizontalPadding)
    }

    private func headerAccessory(
        for activeSelection: ActiveTabSelection,
        context: NotchContext
    ) -> AnyView? {
        switch activeSelection {
        case .group(let group):
            return group.headerAccessory()
        case .plugin(let plugin):
            return (plugin as? any NotchPluginHeaderAccessoryRendering)?
                .headerAccessory(context: context, isOpenPinned: session.isOpenPinned)
        case .none:
            return nil
        }
    }

    private func handleGlobalDropStateChange(_ state: NotchGlobalDropStripState) {
        globalDropResultClearTask?.cancel()
        globalDropResultClearTask = nil
        withAnimation(ScreenSessionModel.sneakAnimation) {
            session.setGlobalDropStripState(state)
        }
    }

    private func handleGlobalDropCompleted(_ state: NotchGlobalDropStripState) {
        withAnimation(ScreenSessionModel.sneakAnimation) {
            session.setGlobalDropStripState(state)
        }
        scheduleGlobalDropResultClear()
    }

    private func scheduleGlobalDropResultClear() {
        globalDropResultClearTask?.cancel()
        globalDropResultClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard Task.isCancelled == false else {
                return
            }
            withAnimation(ScreenSessionModel.sneakAnimation) {
                session.setGlobalDropStripState(.inactive)
            }
            globalDropResultClearTask = nil
        }
    }

    @MainActor
    private enum HeaderTab {
        case plugin(any NotchPlugin)
        case group(NotchPluginTabCollection.Group)

        var id: String {
            switch self {
            case .plugin(let p): return p.id
            case .group(let group): return group.id
            }
        }
    }

    @MainActor
    private enum ActiveTabSelection {
        case plugin(any NotchPlugin)
        case group(NotchPluginTabCollection.Group)
        case none

        var id: String? {
            switch self {
            case .plugin(let plugin):
                return plugin.id
            case .group(let group):
                return group.id
            case .none:
                return nil
            }
        }
    }

    private func headerTabs(tabs: NotchPluginTabCollection) -> [HeaderTab] {
        let pluginTabs: [(order: Int, title: String, tab: HeaderTab)] = tabs.pluginTabs.map {
            ($0.dockOrder, $0.title, .plugin($0))
        }
        let groupTabs: [(order: Int, title: String, tab: HeaderTab)] = tabs.groupTabs.map {
            ($0.dockOrder, $0.title, .group($0))
        }

        return (pluginTabs + groupTabs)
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.title < rhs.title
                }
                return lhs.order < rhs.order
            }
            .map(\.tab)
    }

    private func groupTabButton(
        group: NotchPluginTabCollection.Group,
        isActive: Bool
    ) -> some View {
        Button {
            session.activePluginID = group.id
        } label: {
            ZStack {
                Image(systemName: group.iconSystemName)
                    .font(.system(size: NotchExpandedLayout.pluginTabIconSize - 2, weight: .bold))
                    .foregroundStyle(isActive ? NotchPilotTheme.islandTextPrimary : group.accentColor)
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
                                        group.accentColor.opacity(0.2),
                                        group.accentColor.opacity(0.08),
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
                        isActive ? group.accentColor.opacity(0.18) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.title)
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
                                        plugin.accentColor.opacity(0.24),
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
            return AppStrings.text(.media, language: language)
        case SettingsPluginID.notes.rawValue:
            return AppStrings.text(.notes, language: language)
        case SettingsPluginID.systemMonitor.rawValue:
            return AppStrings.text(.system, language: language)
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
        .accessibilityLabel(AppStrings.text(.openSettings, language: language))
    }

    private func activeSelection(
        in tabs: NotchPluginTabCollection,
        resolvedActiveID: String?
    ) -> ActiveTabSelection {
        if let activeID = resolvedActiveID {
            if let group = tabs.group(id: activeID) {
                return .group(group)
            }
            if let plugin = tabs.plugin(id: activeID) {
                return .plugin(plugin)
            }
        }

        guard let fallbackID = tabs.defaultTabID else {
            return .none
        }

        session.activePluginID = fallbackID
        if let group = tabs.group(id: fallbackID) {
            return .group(group)
        }
        if let plugin = tabs.plugin(id: fallbackID) {
            return .plugin(plugin)
        }
        return .none
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }
}
