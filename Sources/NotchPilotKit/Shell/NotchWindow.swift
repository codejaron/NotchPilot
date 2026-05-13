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

enum NotchWindowStyle {
    static let defaultStyleMask: NSWindow.StyleMask = [
        .borderless,
        .nonactivatingPanel,
        .utilityWindow,
    ]
}

@MainActor
public final class NotchWindow: NSPanel {
    private unowned let session: ScreenSessionModel
    private let pluginManager: PluginManager
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var lastHoverState: Bool?
    private var pluginObserver: AnyCancellable?
    private var accumulatedTabScrollDelta = CGSize.zero
    private var tabScrollGestureLocked = false

    public init(session: ScreenSessionModel, pluginManager: PluginManager) {
        self.session = session
        self.pluginManager = pluginManager
        super.init(
            contentRect: session.windowFrame,
            styleMask: NotchWindowStyle.defaultStyleMask,
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
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
        ignoresMouseEvents = false
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
        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel,
            .swipe
        ]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            var shouldConsumeEvent = false
            MainActor.assumeIsolated {
                self?.updateMouseInteraction()
                shouldConsumeEvent = self?.handleTabGesture(event) == true
            }
            if shouldConsumeEvent {
                return nil
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMouseInteraction()
            }
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func observePluginUpdates() {
        pluginObserver = pluginManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.refreshFrame(animated: true)
            }
        }
    }

    private func updateMouseInteraction() {
        let metrics = NotchLayoutMetrics.resolve(session: session, plugins: pluginManager.enabledPlugins)
        let interactionFrame = session.interactionFrame(for: metrics.interactionSize)
        let hovering = interactionFrame.contains(NSEvent.mouseLocation)

        guard hovering != lastHoverState else {
            return
        }

        lastHoverState = hovering
        ignoresMouseEvents = !hovering
        session.setHover(hovering, fallbackPluginID: pluginManager.enabledPlugins.first?.id)
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
            direction: direction
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
