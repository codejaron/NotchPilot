import AppKit
import Combine
import SwiftUI

@MainActor
public final class NotchWindow: NSPanel {
    private unowned let session: ScreenSessionModel
    private let pluginManager: PluginManager
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var lastHoverState = false
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
        let targetFrame = session.windowFrame

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
            Task { @MainActor [weak self] in
                self?.updateMouseInteraction()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor [weak self] in
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

        ignoresMouseEvents = !hovering

        guard hovering != lastHoverState else {
            return
        }

        lastHoverState = hovering
        session.setHover(hovering, fallbackPluginID: pluginManager.enabledPlugins.first?.id)
    }
}
