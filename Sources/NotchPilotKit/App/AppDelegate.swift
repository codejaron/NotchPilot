import AppKit
import Foundation

@MainActor
public final class NotchPilotAppDelegate: NSObject, NSApplicationDelegate {
    private let bus = EventBus()
    private let pluginManager = PluginManager()
    private let claudePlugin = ClaudePlugin()
    private let codexPlugin = CodexPlugin()
    private let settingsController = SettingsWindowController()

    private var multiScreenManager: MultiScreenManager?
    private var statusItemController: StatusItemController?
    private var socketServer: UnixDomainSocketServer?
    private var settingsObserver: NSObjectProtocol?
    private var socketPreferenceObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        NSApp.setActivationPolicy(.regular)
#else
        NSApp.setActivationPolicy(.accessory)
#endif

        for plugin in initialPlugins() {
            pluginManager.register(plugin)
        }
        pluginManager.activateAll(using: bus)

        let multiScreenManager = MultiScreenManager(bus: bus, pluginManager: pluginManager)
        multiScreenManager.start()
        self.multiScreenManager = multiScreenManager

        statusItemController = StatusItemController(
            openHandler: { [weak self] in
                guard let self else { return }
                guard let pluginID = self.pluginManager.defaultOpenPluginID(
                    previewPluginID: nil,
                    lastSelectedPluginID: nil
                ) else {
                    return
                }
                self.bus.emit(.openRequested(pluginID: pluginID, target: .activeScreen))
            },
            closeHandler: { [weak self] in
                self?.bus.emit(.closeRequested(target: .allScreens))
            },
            settingsHandler: { [weak self] in
                self?.settingsController.showSettings()
            },
            quitHandler: {
                NSApp.terminate(nil)
            }
        )

        applySocketPreference()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .openSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.settingsController.showSettings()
            }
        }

        socketPreferenceObserver = NotificationCenter.default.addObserver(
            forName: .bridgeSocketPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applySocketPreference()
            }
        }

#if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
        }
#endif
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let socketPreferenceObserver {
            NotificationCenter.default.removeObserver(socketPreferenceObserver)
        }
        socketServer?.stop()
        multiScreenManager?.stop()
        pluginManager.deactivateAll()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func applySocketPreference() {
        if SettingsStore.shared.autoStartSocket {
            startSocketServer()
        } else {
            stopSocketServer()
        }
    }

    private func startSocketServer() {
        guard socketServer == nil else {
            return
        }

        let server = UnixDomainSocketServer(socketPath: BridgeSocketConfiguration.default.socketPath)
        do {
            try server.start(
                onFrame: { [weak self] frame, respond in
                    Task { @MainActor [weak self] in
                        self?.claudePlugin.handle(frame: frame, respond: respond)
                    }
                },
                onDisconnect: { [weak self] requestID in
                    Task { @MainActor [weak self] in
                        self?.claudePlugin.handleDisconnect(requestID: requestID)
                    }
                }
            )
            socketServer = server
        } catch {
            NSLog("NotchPilot failed to start the bridge socket: \(error.localizedDescription)")
        }
    }

    private func stopSocketServer() {
        socketServer?.stop()
        socketServer = nil
    }

    func initialPlugins() -> [any NotchPlugin] {
        [claudePlugin, codexPlugin]
    }

    var registeredPluginIDsForTesting: [String] {
        initialPlugins().map(\.id)
    }
}

public extension Notification.Name {
    static let openSettings = Notification.Name("NotchPilot.openSettings")
    static let bridgeSocketPreferenceChanged = Notification.Name("NotchPilot.bridgeSocketPreferenceChanged")
}
