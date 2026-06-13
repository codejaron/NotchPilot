import AppKit
import Foundation

@MainActor
public final class MultiScreenManager {
    public private(set) var sessions: [String: ScreenSessionModel] = [:]

    private let bus: EventBus
    private let pluginManager: PluginManager
    private let screenDescriptorProvider: @MainActor () -> [ScreenDescriptor]
    private let activeScreenIDProvider: @MainActor () -> String?
    private let primaryScreenIDProvider: @MainActor () -> String?
    private let windowFactory: @MainActor (ScreenSessionModel, PluginManager) -> NotchWindow?

    private var windows: [String: NotchWindow] = [:]
    private var busToken: UUID?
    private var screenObserver: NSObjectProtocol?
    private var activeSneakPeekRequests: [SneakPeekRequest] = []
    private var connectedDescriptors: [ScreenDescriptor] = []

    public convenience init(bus: EventBus, pluginManager: PluginManager) {
        self.init(
            bus: bus,
            pluginManager: pluginManager,
            screenDescriptorProvider: Self.defaultScreenDescriptors,
            activeScreenIDProvider: Self.defaultActiveScreenID,
            primaryScreenIDProvider: Self.defaultPrimaryScreenID,
            windowFactory: { session, pluginManager in
                NotchWindow(session: session, pluginManager: pluginManager)
            }
        )
    }

    init(
        bus: EventBus,
        pluginManager: PluginManager,
        screenDescriptorProvider: @escaping @MainActor () -> [ScreenDescriptor],
        activeScreenIDProvider: @escaping @MainActor () -> String?,
        primaryScreenIDProvider: @escaping @MainActor () -> String?,
        windowFactory: @escaping @MainActor (ScreenSessionModel, PluginManager) -> NotchWindow?
    ) {
        self.bus = bus
        self.pluginManager = pluginManager
        self.screenDescriptorProvider = screenDescriptorProvider
        self.activeScreenIDProvider = activeScreenIDProvider
        self.primaryScreenIDProvider = primaryScreenIDProvider
        self.windowFactory = windowFactory
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
        connectedDescriptors.removeAll()
        activeSneakPeekRequests.removeAll()
    }

    func synchronizeScreens() {
        let descriptors = screenDescriptorProvider()
        let nextIDs = Set(descriptors.map(\.id))
        var newSessionIDs: [String] = []

        for descriptor in descriptors {
            if let existing = sessions[descriptor.id] {
                existing.updateScreen(descriptor)
            } else {
                let session = ScreenSessionModel(
                    descriptor: descriptor,
                    activePluginIDResolver: pluginManager.resolvedTabID
                )
                session.activePluginID = pluginManager.defaultOpenPluginID(
                    previewPluginID: nil,
                    lastSelectedPluginID: nil
                )
                sessions[descriptor.id] = session
                windows[descriptor.id] = windowFactory(session, pluginManager)
                newSessionIDs.append(descriptor.id)
            }
        }

        let obsoleteIDs = Set(sessions.keys).subtracting(nextIDs)
        for id in obsoleteIDs {
            windows[id]?.close()
            windows.removeValue(forKey: id)
            sessions.removeValue(forKey: id)
        }

        connectedDescriptors = descriptors.filter { sessions[$0.id] != nil }
        replayActiveSneakPeekRequests(to: Set(newSessionIDs))
    }

    func handle(event: NotchEvent) {
        let context = screenResolutionContext()

        switch event {
        case let .sneakPeekRequested(request):
            rememberActiveSneakPeekRequestIfNeeded(request)
            for id in PresentationTargetResolver.resolve(request.target, in: context) {
                sessions[id]?.enqueue(request)
            }
        case let .updateSneakPeekPriority(requestID, priority, target):
            updateActiveSneakPeekRequest(requestID: requestID, priority: priority)
            for id in PresentationTargetResolver.resolve(target, in: context) {
                sessions[id]?.updateSneakPeekPriority(requestID: requestID, priority: priority)
            }
        case let .dismissSneakPeek(requestID, target):
            let resolvedIDs = PresentationTargetResolver.resolve(target, in: context)
            forgetActiveSneakPeekRequest(requestID: requestID, resolvedSessionIDs: resolvedIDs)
            for id in resolvedIDs {
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

    private func replayActiveSneakPeekRequests(to sessionIDs: Set<String>) {
        guard sessionIDs.isEmpty == false, activeSneakPeekRequests.isEmpty == false else {
            return
        }

        let context = screenResolutionContext()
        for request in activeSneakPeekRequests {
            let resolvedIDs = Set(PresentationTargetResolver.resolve(request.target, in: context))
            for id in sessionIDs where resolvedIDs.contains(id) {
                sessions[id]?.enqueue(request)
            }
        }
    }

    private func rememberActiveSneakPeekRequestIfNeeded(_ request: SneakPeekRequest) {
        guard request.autoDismissAfter == nil else {
            return
        }

        if let index = activeSneakPeekRequests.firstIndex(where: { $0.id == request.id }) {
            activeSneakPeekRequests[index] = request
        } else {
            activeSneakPeekRequests.append(request)
        }
    }

    private func updateActiveSneakPeekRequest(requestID: UUID, priority: Int) {
        guard let index = activeSneakPeekRequests.firstIndex(where: { $0.id == requestID }) else {
            return
        }

        let existing = activeSneakPeekRequests[index]
        activeSneakPeekRequests[index] = SneakPeekRequest(
            id: existing.id,
            pluginID: existing.pluginID,
            priority: priority,
            target: existing.target,
            kind: existing.kind,
            isInteractive: existing.isInteractive,
            autoDismissAfter: existing.autoDismissAfter,
            createdAt: existing.createdAt
        )
    }

    private func forgetActiveSneakPeekRequest(
        requestID: UUID?,
        resolvedSessionIDs: [String]
    ) {
        if let requestID {
            activeSneakPeekRequests.removeAll { $0.id == requestID }
            return
        }

        let currentRequestIDs = Set(resolvedSessionIDs.compactMap {
            sessions[$0]?.currentSneakPeek?.id
        })
        activeSneakPeekRequests.removeAll { currentRequestIDs.contains($0.id) }
    }

    private func screenResolutionContext() -> ScreenResolutionContext {
        ScreenResolutionContext(
            connectedScreens: connectedDescriptors,
            activeScreenID: activeScreenIDProvider(),
            primaryScreenID: primaryScreenIDProvider()
        )
    }

    private static func defaultScreenDescriptors() -> [ScreenDescriptor] {
        NSScreen.screens.compactMap {
            ScreenDescriptorFactory.descriptor(for: $0, includeClosedNotchSize: true)
        }
    }

    private static func defaultActiveScreenID() -> String? {
        let location = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(location) {
            return ScreenDescriptorFactory.screenID(for: screen)
        }
        return nil
    }

    private static func defaultPrimaryScreenID() -> String? {
        NSScreen.screens.first.flatMap(ScreenDescriptorFactory.screenID(for:))
    }
}
