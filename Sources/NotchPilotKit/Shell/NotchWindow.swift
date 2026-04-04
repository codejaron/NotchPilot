import AppKit
import SwiftUI

@MainActor
public final class NotchWindow: NSPanel {
    private unowned let session: ScreenSessionModel

    public init(session: ScreenSessionModel, pluginManager: PluginManager) {
        self.session = session
        super.init(
            contentRect: session.windowFrame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
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

        contentView = NSHostingView(rootView: NotchContentView(session: session, pluginManager: pluginManager))
        orderFrontRegardless()

        session.layoutDidChange = { [weak self] in
            self?.refreshFrame(animated: true)
        }
    }

    public func refreshFrame(animated: Bool) {
        let targetFrame = session.windowFrame

        guard animated else {
            setContentSize(targetFrame.size)
            setFrameOrigin(targetFrame.origin)
            displayIfNeeded()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            animator().setContentSize(targetFrame.size)
            animator().setFrameOrigin(targetFrame.origin)
        }
    }
}
