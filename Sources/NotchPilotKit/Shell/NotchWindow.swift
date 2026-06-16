import AppKit
import Combine
import SwiftUI

struct NotchWindowFrameRefreshPlan: Equatable {
    let targetFrame: CGRect
    let needsWindowFrameUpdate: Bool

    static func resolve(currentFrame: CGRect, targetFrame: CGRect) -> NotchWindowFrameRefreshPlan {
        NotchWindowFrameRefreshPlan(
            targetFrame: targetFrame,
            needsWindowFrameUpdate: currentFrame.equalTo(targetFrame) == false
        )
    }
}

struct NotchWindowInteractionFrameCache {
    private var cachedFrame: CGRect?

    mutating func frame(resolve: () -> CGRect) -> CGRect {
        if let cachedFrame {
            return cachedFrame
        }

        let frame = resolve()
        cachedFrame = frame
        return frame
    }

    mutating func invalidate() {
        cachedFrame = nil
    }
}

enum NotchWindowStyle {
    static let defaultStyleMask: NSWindow.StyleMask = [
        .borderless,
        .nonactivatingPanel,
        .utilityWindow,
    ]
}

enum NotchWindowMouseEventPolicy {
    static func ignoresMouseEvents(
        notchState: NotchState,
        isHoveringInteractionFrame: Bool,
        isGlobalFileDragActive: Bool,
        isGlobalDropStripVisible: Bool
    ) -> Bool {
        if isGlobalFileDragActive || isGlobalDropStripVisible {
            return false
        }

        guard notchState == .open else {
            return true
        }

        return isHoveringInteractionFrame == false
    }
}

@MainActor
public final class NotchWindow: NSPanel {
    private unowned let session: ScreenSessionModel
    private let pluginManager: PluginManager
    private let mouseActivityMonitor: any MouseActivityMonitoring
    private let globalDragPasteboardReader: any NotchGlobalDragPasteboardReading
    private var mouseActivityToken: UUID?
    private var lastHoverState: Bool?
    private var pluginObserver: AnyCancellable?
    private var accumulatedTabScrollDelta = CGSize.zero
    private var tabScrollGestureLocked = false
    private var interactionFrameCache = NotchWindowInteractionFrameCache()
    private var observedGlobalDragPasteboardChangeCount: Int?
    private var activeGlobalFileDragPasteboardChangeCount: Int?
    private var isGlobalFileDragActive = false

    public convenience init(session: ScreenSessionModel, pluginManager: PluginManager) {
        self.init(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: MouseActivityMonitor.shared,
            globalDragPasteboardReader: NotchGlobalDragPasteboardReader()
        )
    }

    init(
        session: ScreenSessionModel,
        pluginManager: PluginManager,
        mouseActivityMonitor: any MouseActivityMonitoring,
        globalDragPasteboardReader: any NotchGlobalDragPasteboardReading = NotchGlobalDragPasteboardReader()
    ) {
        self.session = session
        self.pluginManager = pluginManager
        self.mouseActivityMonitor = mouseActivityMonitor
        self.globalDragPasteboardReader = globalDragPasteboardReader
        super.init(
            contentRect: session.windowFrame,
            styleMask: NotchWindowStyle.defaultStyleMask,
            backing: .buffered,
            defer: false
        )

        observedGlobalDragPasteboardChangeCount = globalDragPasteboardReader.snapshot().changeCount
        isFloatingPanel = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true

        contentView = NSHostingView(rootView: NotchContentView(session: session, pluginManager: pluginManager))
        orderFrontRegardless()
        installMouseMonitors()
        observePluginUpdates()
        updateMouseInteraction()

        session.layoutDidChange = { [weak self] in
            self?.refreshFrame(animated: true)
        }
    }

    override public var canBecomeKey: Bool {
        true
    }

    override public var canBecomeMain: Bool {
        true
    }

    public func refreshFrame(animated: Bool) {
        interactionFrameCache.invalidate()
        let refreshPlan = NotchWindowFrameRefreshPlan.resolve(
            currentFrame: frame,
            targetFrame: session.windowFrame
        )

        guard refreshPlan.needsWindowFrameUpdate else {
            updateMouseInteraction()
            return
        }

        let targetFrame = refreshPlan.targetFrame
        guard animated else {
            setContentSize(targetFrame.size)
            setFrameOrigin(targetFrame.origin)
            displayIfNeeded()
            updateMouseInteraction()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            animator().setContentSize(targetFrame.size)
            animator().setFrameOrigin(targetFrame.origin)
        }
        updateMouseInteraction()
    }

    override public func close() {
        removeMouseMonitors()
        pluginObserver = nil
        super.close()
    }

    private func installMouseMonitors() {
        guard mouseActivityToken == nil else {
            return
        }

        mouseActivityToken = mouseActivityMonitor.addSubscriber { [weak self] activity in
            guard let self else {
                return .passThrough
            }

            self.updateGlobalFileDragState(for: activity.event)
            self.updateMouseInteraction()
            guard activity.scope == .local,
                  self.handleTabGesture(activity.event) else {
                return .passThrough
            }

            return .consumeEvent
        }
    }

    private func removeMouseMonitors() {
        if let mouseActivityToken {
            mouseActivityMonitor.removeSubscriber(mouseActivityToken)
            self.mouseActivityToken = nil
        }
    }

    private func observePluginUpdates() {
        pluginObserver = pluginManager.layoutInvalidated.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.refreshFrame(animated: true)
            }
        }
    }

    private func updateMouseInteraction() {
        let interactionFrame = interactionFrameCache.frame { [session, pluginManager] in
            let metrics = NotchLayoutMetrics.resolve(session: session, plugins: pluginManager.enabledPlugins)
            return session.interactionFrame(for: metrics.interactionSize)
        }
        let hovering = interactionFrame.contains(NSEvent.mouseLocation)
        ignoresMouseEvents = NotchWindowMouseEventPolicy.ignoresMouseEvents(
            notchState: session.notchState,
            isHoveringInteractionFrame: hovering,
            isGlobalFileDragActive: isGlobalFileDragActive,
            isGlobalDropStripVisible: session.globalDropStripState.isVisible
        )

        guard hovering != lastHoverState else {
            return
        }

        lastHoverState = hovering
        session.setHover(hovering, fallbackPluginID: pluginManager.enabledPlugins.first?.id)
    }

    private func updateGlobalFileDragState(for event: NSEvent) {
        guard NotchGlobalDragReducer.shouldInspectPasteboard(for: event.type) else {
            return
        }

        let snapshot = globalDragPasteboardReader.snapshot()
        let nextState = NotchGlobalDragReducer.state(
            eventType: event.type,
            fileURLCount: globalDragFileURLCount(eventType: event.type, snapshot: snapshot),
            currentState: session.globalDropStripState,
            handler: NotchGlobalDropHandler(
                notesPlugin: { [pluginManager] in
                    pluginManager.registeredPlugin(id: SettingsPluginID.notes.rawValue) as? NotesPlugin
                },
                selectNotes: { [session] in
                    session.activePluginID = SettingsPluginID.notes.rawValue
                }
            )
        )

        guard let nextState else {
            return
        }
        session.setGlobalDropStripState(nextState)
    }

    private func globalDragFileURLCount(
        eventType: NSEvent.EventType,
        snapshot: NotchGlobalDragPasteboardSnapshot
    ) -> Int {
        switch eventType {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard snapshot.supportedFileURLCount > 0 else {
                observedGlobalDragPasteboardChangeCount = snapshot.changeCount
                activeGlobalFileDragPasteboardChangeCount = nil
                isGlobalFileDragActive = false
                return 0
            }

            if activeGlobalFileDragPasteboardChangeCount == snapshot.changeCount {
                isGlobalFileDragActive = true
                return snapshot.supportedFileURLCount
            }

            guard observedGlobalDragPasteboardChangeCount != snapshot.changeCount else {
                isGlobalFileDragActive = false
                return 0
            }

            observedGlobalDragPasteboardChangeCount = snapshot.changeCount
            activeGlobalFileDragPasteboardChangeCount = snapshot.changeCount
            isGlobalFileDragActive = true
            return snapshot.supportedFileURLCount
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            observedGlobalDragPasteboardChangeCount = snapshot.changeCount
            activeGlobalFileDragPasteboardChangeCount = nil
            isGlobalFileDragActive = false
            return 0
        default:
            return 0
        }
    }

    private func handleTabGesture(_ event: NSEvent) -> Bool {
        guard
            session.notchState == .open,
            lastHoverState == true,
            shouldHandleShellTabGesture(for: event)
        else {
            resetAccumulatedTabScrollDelta()
            return false
        }

        switch event.type {
        case .scrollWheel:
            return handleTabScroll(event)
        case .swipe:
            return handleTabSwipe(event)
        default:
            return false
        }
    }

    private func handleTabScroll(_ event: NSEvent) -> Bool {
        if event.phase == .began || event.phase == .mayBegin {
            resetAccumulatedTabScrollDelta()
        }

        if tabScrollGestureLocked {
            if scrollGestureDidEnd(event) {
                resetAccumulatedTabScrollDelta()
            }
            return true
        }

        guard event.momentumPhase.isEmpty else {
            return false
        }

        accumulatedTabScrollDelta.width += event.scrollingDeltaX
        accumulatedTabScrollDelta.height += event.scrollingDeltaY

        guard let direction = NotchTabGestureIntent.direction(
            horizontalDelta: accumulatedTabScrollDelta.width,
            verticalDelta: accumulatedTabScrollDelta.height
        ) else {
            if event.phase == .ended || event.phase == .cancelled {
                resetAccumulatedTabScrollDelta()
            }
            return false
        }

        guard switchActiveTab(direction) else {
            resetAccumulatedTabScrollDelta()
            return false
        }

        resetAccumulatedTabScrollDelta()
        if event.phase.isEmpty == false {
            tabScrollGestureLocked = true
        }
        return true
    }

    private func handleTabSwipe(_ event: NSEvent) -> Bool {
        guard let direction = NotchTabGestureIntent.direction(
            horizontalDelta: event.deltaX,
            verticalDelta: event.deltaY,
            minimumHorizontalDelta: 0.5,
            horizontalDominanceRatio: 1.1
        ) else {
            return false
        }

        return switchActiveTab(direction)
    }

    private func switchActiveTab(_ direction: NotchTabNavigator.Direction) -> Bool {
        guard let destination = NotchTabNavigator.destination(
            from: session.activePluginID,
            orderedTabIDs: NotchTabNavigator.orderedTabIDs(from: pluginManager.enabledPlugins),
            direction: direction,
            resolveTabID: pluginManager.resolvedTabID
        ) else {
            return false
        }

        session.activePluginID = destination
        return true
    }

    private func resetAccumulatedTabScrollDelta() {
        accumulatedTabScrollDelta = .zero
        tabScrollGestureLocked = false
    }

    private func shouldHandleShellTabGesture(for event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return false
        }

        return (firstResponder is NSTextView) == false
    }

    private func scrollGestureDidEnd(_ event: NSEvent) -> Bool {
        event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled)
    }
}
