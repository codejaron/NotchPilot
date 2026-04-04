import AppKit
import Foundation

@MainActor
public final class MultiScreenManager {
    public private(set) var sessions: [String: ScreenSessionModel] = [:]

    private let bus: EventBus
    private let pluginManager: PluginManager

    private var windows: [String: NotchWindow] = [:]
    private var busToken: UUID?
    private var screenObserver: NSObjectProtocol?

    public init(bus: EventBus, pluginManager: PluginManager) {
        self.bus = bus
        self.pluginManager = pluginManager
    }

    public func start() {
        synchronizeScreens()
        busToken = bus.subscribe { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.synchronizeScreens()
            }
        }
    }

    public func stop() {
        if let busToken {
            bus.unsubscribe(busToken)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        windows.values.forEach { $0.close() }
        windows.removeAll()
        sessions.removeAll()
    }

    private func synchronizeScreens() {
        let descriptors = NSScreen.screens.compactMap(screenDescriptor(for:))
        let nextIDs = Set(descriptors.map(\.id))

        for descriptor in descriptors {
            if let existing = sessions[descriptor.id] {
                existing.updateScreen(descriptor)
            } else {
                let session = ScreenSessionModel(descriptor: descriptor)
                session.activePluginID = pluginManager.enabledPlugins.first?.id
                sessions[descriptor.id] = session
                windows[descriptor.id] = NotchWindow(session: session, pluginManager: pluginManager)
            }
        }

        let obsoleteIDs = Set(sessions.keys).subtracting(nextIDs)
        for id in obsoleteIDs {
            windows[id]?.close()
            windows.removeValue(forKey: id)
            sessions.removeValue(forKey: id)
        }
    }

    private func handle(event: NotchEvent) {
        let context = ScreenResolutionContext(
            connectedScreens: sessions.values.map(\.descriptor),
            activeScreenID: activeScreenID(),
            primaryScreenID: NSScreen.main.flatMap(screenID(for:))
        )

        switch event {
        case let .sneakPeekRequested(request):
            for id in PresentationTargetResolver.resolve(request.target, in: context) {
                sessions[id]?.enqueue(request)
            }
        case let .dismissSneakPeek(requestID, target):
            for id in PresentationTargetResolver.resolve(target, in: context) {
                sessions[id]?.dismissSneakPeek(requestID: requestID)
            }
        case let .openRequested(pluginID, target):
            for id in PresentationTargetResolver.resolve(target, in: context) {
                sessions[id]?.open(pluginID: pluginID)
            }
        case let .closeRequested(target):
            for id in PresentationTargetResolver.resolve(target, in: context) {
                sessions[id]?.close()
            }
        }
    }

    private func activeScreenID() -> String? {
        let location = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(location) {
            return screenID(for: screen)
        }
        return nil
    }

    private func screenDescriptor(for screen: NSScreen) -> ScreenDescriptor? {
        guard let id = screenID(for: screen) else {
            return nil
        }

        return ScreenDescriptor(
            id: id,
            frame: screen.frame,
            isPrimary: screen == NSScreen.main,
            closedNotchSize: NotchSizing.closedCompactSize(
                screenFrame: screen.frame,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
                safeAreaTopInset: screen.safeAreaInsets.top,
                menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
            )
        )
    }

    private func screenID(for screen: NSScreen) -> String? {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(screenNumber.uint32Value)
        }

        return screen.localizedName
    }
}
