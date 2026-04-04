import AppKit
import Foundation

@MainActor
public final class NotchPilotAppDelegate: NSObject, NSApplicationDelegate {
    private let bus = EventBus()
    private let pluginManager = PluginManager()
    private let aiPlugin = AIAgentPlugin()

    private var multiScreenManager: MultiScreenManager?
    private var statusItemController: StatusItemController?
    private var socketServer: UnixDomainSocketServer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        NSApp.setActivationPolicy(.regular)
#else
        NSApp.setActivationPolicy(.accessory)
#endif

        pluginManager.register(aiPlugin)
        pluginManager.activateAll(using: bus)

        let multiScreenManager = MultiScreenManager(bus: bus, pluginManager: pluginManager)
        multiScreenManager.start()
        self.multiScreenManager = multiScreenManager

        statusItemController = StatusItemController(
            openHandler: { [weak self] in
                guard let self else { return }
                self.bus.emit(.openRequested(pluginID: self.aiPlugin.id, target: .activeScreen))
            },
            closeHandler: { [weak self] in
                self?.bus.emit(.closeRequested(target: .allScreens))
            },
            quitHandler: {
                NSApp.terminate(nil)
            }
        )

        let server = UnixDomainSocketServer(socketPath: BridgeSocketConfiguration.default.socketPath)
        do {
            try server.start(
                onFrame: { [weak self] frame, respond in
                    Task { @MainActor [weak self] in
                        self?.aiPlugin.handle(frame: frame, respond: respond)
                    }
                },
                onDisconnect: { [weak self] requestID in
                    Task { @MainActor [weak self] in
                        self?.aiPlugin.handleDisconnect(requestID: requestID)
                    }
                }
            )
            socketServer = server
        } catch {
            NSLog("NotchPilot failed to start the bridge socket: \(error.localizedDescription)")
        }

#if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
        }
#endif
    }

    public func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        multiScreenManager?.stop()
        pluginManager.deactivateAll()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
#if DEBUG
        true
#else
        false
#endif
    }
}
