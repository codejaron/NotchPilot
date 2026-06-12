import AppKit
import Foundation
import KeyboardShortcuts

@MainActor
public final class NotchPilotAppDelegate: NSObject, NSApplicationDelegate {
    private let bus = EventBus()
    private let pluginManager = PluginManager()
    private let nowPlayingController = SharedNowPlayingController()
    private let settingsStore = SettingsStore.shared
    private let generalSettings = SettingsStore.shared.general
    private let bridgeSettings = SettingsStore.shared.bridge
    private lazy var mediaPlaybackPlugin = MediaPlaybackPlugin(monitor: nowPlayingController)
    private let claudePlugin = ClaudePlugin()
    private let codexPlugin = CodexPlugin()
    private let systemMonitorPlugin = SystemMonitorPlugin()
    private lazy var bridgeDispatcher = AIBridgeDispatcher(handlers: [claudePlugin])
    private let settingsController = SettingsWindowController()

    private var multiScreenManager: MultiScreenManager?
    private var desktopLyricsManager: DesktopLyricsManager?
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

        let multiScreenManager = MultiScreenManager(bus: bus, pluginManager: pluginManager)
        multiScreenManager.start()
        self.multiScreenManager = multiScreenManager
        pluginManager.activateAll(using: bus)

        let lyricsCache = LyricsCache(homeDirectoryURL: settingsStore.homeDirectoryURL)
        let lyricsRemoteProvider = LyricsKitProvider()
        let desktopLyricsManager = DesktopLyricsManager(
            nowPlayingController: nowPlayingController,
            settingsStore: .shared,
            provider: CachedLyricsProvider(
                cache: lyricsCache,
                remoteProvider: lyricsRemoteProvider
            ),
            searchProvider: lyricsRemoteProvider,
            cache: lyricsCache,
            ignoredTrackStore: IgnoredLyricsTrackStore()
        )
        desktopLyricsManager.start()
        self.desktopLyricsManager = desktopLyricsManager

        statusItemController = StatusItemController(
            lyricsActions: desktopLyricsManager.statusMenuActions,
            activitySneakActions: StatusItemActivitySneakActions(
                isHidden: { [weak self] in
                    self?.generalSettings.activitySneakPreviewsHidden ?? false
                },
                toggle: { [weak self] in
                    self?.generalSettings.activitySneakPreviewsHidden.toggle()
                }
            ),
            settingsHandler: { [weak self] in
                self?.settingsController.showSettings()
            },
            quitHandler: {
                NSApp.terminate(nil)
            }
        )

        applySocketPreference()

        KeyboardShortcuts.onKeyDown(for: .toggleHideAllPreviews) {
            Task { @MainActor [weak self] in
                self?.generalSettings.activitySneakPreviewsHidden.toggle()
            }
        }

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

    public func applicationDidBecomeActive(_ notification: Notification) {
        generalSettings.refreshLaunchAtLoginState()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let socketPreferenceObserver {
            NotificationCenter.default.removeObserver(socketPreferenceObserver)
        }
        socketServer?.stop()
        desktopLyricsManager?.stop()
        multiScreenManager?.stop()
        pluginManager.deactivateAll()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func applySocketPreference() {
        if bridgeSettings.autoStartSocket {
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
                        self?.bridgeDispatcher.handle(frame: frame, respond: respond)
                    }
                },
                onDisconnect: { [weak self] requestID in
                    Task { @MainActor [weak self] in
                        self?.bridgeDispatcher.handleDisconnect(requestID: requestID)
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
        [systemMonitorPlugin, claudePlugin, codexPlugin, mediaPlaybackPlugin]
    }

    var registeredPluginIDsForTesting: [String] {
        initialPlugins().map(\.id)
    }
}

public extension Notification.Name {
    static let openSettings = Notification.Name("NotchPilot.openSettings")
    static let bridgeSocketPreferenceChanged = Notification.Name("NotchPilot.bridgeSocketPreferenceChanged")
}
