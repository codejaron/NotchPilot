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

@MainActor
public final class NotchWindow: NSPanel {
    private unowned let session: ScreenSessionModel
    private let pluginManager: PluginManager
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var lastHoverState: Bool?
    private var pluginObserver: AnyCancellable?

    public init(session: ScreenSessionModel, pluginManager: PluginManager) {
        self.session = session
        self.pluginManager = pluginManager
        super.init(
            contentRect: session.windowFrame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
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
            .otherMouseDragged
        ]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.updateMouseInteraction()
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
}
