import Combine
import SwiftUI

@MainActor
public final class CodexPlugin: AIPluginRendering {
    public let id = "codex"
    public let title = "Codex"
    public let iconSystemName = "terminal"
    public let accentColor: Color = .blue
    public let dockOrder = 110
    public let previewPriority: Int? = 90

    @Published public var isEnabled = true
    @Published public private(set) var sessions: [AISession] = []
    @Published public private(set) var pendingApprovals: [PendingApproval] = []
    @Published public private(set) var codexActionableSurface: CodexActionableSurface?

    private static let codexThreadActivityExpiry: TimeInterval = 24 * 60 * 60

    private let settingsStore: SettingsStore
    private let codexMonitor: any CodexDesktopContextMonitoring & CodexDesktopActionableSurfaceMonitoring
    private let nowProvider: @Sendable () -> Date

    private weak var bus: EventBus?
    private var sneakPeekIDs: [String: UUID] = [:]
    private var codexThreads: CodexThreadRegistry
    private var rawCodexActionableSurface: CodexActionableSurface?

    public init(
        settingsStore: SettingsStore = .shared,
        codexMonitor: any CodexDesktopContextMonitoring & CodexDesktopActionableSurfaceMonitoring = CodexDesktopMonitor(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.codexMonitor = codexMonitor
        self.nowProvider = nowProvider
        self.codexThreads = CodexThreadRegistry(activityExpiry: Self.codexThreadActivityExpiry)
    }

    public func activate(bus: EventBus) {
        self.bus = bus
        codexMonitor.onThreadContextChanged = { [weak self] update in
            self?.performOnMainActor {
                $0.handleCodexThreadContextChange(update)
            }
        }
        codexMonitor.onConnectionStateChanged = { [weak self] state in
            self?.performOnMainActor {
                $0.handleCodexConnectionStateChange(state)
            }
        }
        codexMonitor.onSurfaceChanged = { [weak self] surface in
            self?.performOnMainActor {
                $0.handleCodexSurfaceChange(surface)
            }
        }
        codexMonitor.start()
    }

    public func deactivate() {
        codexMonitor.stop()
        codexMonitor.onThreadContextChanged = nil
        codexMonitor.onConnectionStateChanged = nil
        codexMonitor.onSurfaceChanged = nil
        sneakPeekIDs.removeAll()
        codexThreads.reset()
        rawCodexActionableSurface = nil
        sessions = []
        pendingApprovals = []
        codexActionableSurface = nil
        bus = nil
    }

    var currentCompactActivity: AIPluginCompactActivity? {
        if let codexActionableSurface {
            return AIPluginCompactActivity(
                host: .codex,
                label: codexActionableSurface.options.isEmpty && codexActionableSurface.textInput == nil
                    ? "Action Needed"
                    : "Codex Approval Mirror",
                inputTokenCount: preferredCodexSession(for: codexActionableSurface)?.inputTokenCount,
                outputTokenCount: preferredCodexSession(for: codexActionableSurface)?.outputTokenCount,
                approvalCount: 1,
                sessionTitle: preferredCodexTitle(for: codexActionableSurface)
            )
        }

        guard let session = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first else {
            return nil
        }

        return AIPluginCompactActivity(
            host: session.host,
            label: session.activityLabel,
            inputTokenCount: session.inputTokenCount,
            outputTokenCount: session.outputTokenCount,
            approvalCount: 0,
            sessionTitle: displayTitle(for: session)
        )
    }

    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] {
        sessions
            .map { session in
                let codexSurface = codexSurfaceForSession(session)
                return AIPluginExpandedSessionSummary(
                    id: session.id,
                    host: session.host,
                    title: expandedSessionTitle(for: session),
                    subtitle: codexSurface.map {
                        $0.options.isEmpty && $0.textInput == nil ? "Action Needed" : "Codex Approval Mirror"
                    } ?? session.activityLabel,
                    approvalCount: codexSurface == nil ? 0 : 1,
                    approvalRequestID: nil,
                    codexSurfaceID: codexSurface?.id,
                    updatedAt: session.updatedAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.hasAttention != rhs.hasAttention {
                    return lhs.hasAttention
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public func displayTitle(for session: AISession) -> String? {
        codexThreads.displayTitle(for: session)
    }

    public func preferredCodexTitle(for surface: CodexActionableSurface?) -> String? {
        codexThreads.preferredDisplayTitle(for: surface?.threadID)
    }

    @discardableResult
    public func performCodexAction(_ action: CodexSurfaceAction, surfaceID: String) -> Bool {
        let performed = codexMonitor.perform(action: action, on: surfaceID)
        if performed {
            let previousSurfaceID = rawCodexActionableSurface?.id
            rawCodexActionableSurface = nil
            syncState()
            if let previousSurfaceID {
                dismissSneakPeek(for: previousSurfaceID)
            }
        }
        return performed
    }

    @discardableResult
    public func selectCodexOption(_ optionID: String, surfaceID: String) -> Bool {
        let performed = codexMonitor.selectOption(optionID, on: surfaceID)
        if performed {
            optimisticallyUpdateCodexSurface(surfaceID: surfaceID) { surface in
                surface.selectingOption(optionID)
            }
        }
        return performed
    }

    @discardableResult
    public func updateCodexText(_ text: String, surfaceID: String) -> Bool {
        let performed = codexMonitor.updateText(text, on: surfaceID)
        if performed {
            optimisticallyUpdateCodexSurface(surfaceID: surfaceID) { surface in
                surface.updatingText(text)
            }
        }
        return performed
    }

    func preferredCodexSession(for surface: CodexActionableSurface? = nil) -> AISession? {
        codexThreads.preferredSession(for: surface?.threadID)
    }

    private func codexSurfaceForSession(_ session: AISession) -> CodexActionableSurface? {
        guard session.host == .codex,
              let codexActionableSurface
        else {
            return nil
        }

        return codexThreads.preferredSession(for: codexActionableSurface.threadID)?.id == session.id
            ? codexActionableSurface
            : nil
    }

    nonisolated private func performOnMainActor(
        _ action: @escaping @MainActor (CodexPlugin) -> Void
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                action(self)
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            action(self)
        }
    }

    private func handleCodexThreadContextChange(_ update: CodexThreadUpdate) {
        codexThreads.apply(update)
        syncState()
    }

    private func handleCodexConnectionStateChange(_ state: CodexDesktopConnectionState) {
        settingsStore.updateCodexDesktopConnection(state)
    }

    private func handleCodexSurfaceChange(_ surface: CodexActionableSurface?) {
        let previousSurfaceID = rawCodexActionableSurface?.id
        rawCodexActionableSurface = surface
        syncState()

        if let previousSurfaceID, previousSurfaceID != surface?.id {
            dismissSneakPeek(for: previousSurfaceID)
        }
        if let surfaceID = surface?.id, previousSurfaceID != surfaceID {
            presentSneakPeek(for: surfaceID)
        }
    }

    private func optimisticallyUpdateCodexSurface(
        surfaceID: String,
        transform: (CodexActionableSurface) -> CodexActionableSurface
    ) {
        guard let rawCodexActionableSurface, rawCodexActionableSurface.id == surfaceID else {
            return
        }

        self.rawCodexActionableSurface = transform(rawCodexActionableSurface)
        syncState()
    }

    private func syncState() {
        codexThreads.prune(now: nowProvider())
        sessions = codexThreads.sessions()
        codexActionableSurface = mergedCodexSurface()
    }

    private func mergedCodexSurface() -> CodexActionableSurface? {
        guard let rawCodexActionableSurface else {
            return nil
        }

        let context = codexThreads.preferredContext(for: rawCodexActionableSurface.threadID)
        return rawCodexActionableSurface.merged(with: context)
    }

    private func presentSneakPeek(for requestID: String) {
        guard sneakPeekIDs[requestID] == nil else {
            return
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: 1000,
            target: .activeScreen,
            isInteractive: true,
            autoDismissAfter: nil
        )
        sneakPeekIDs[requestID] = request.id
        bus?.emit(.sneakPeekRequested(request))
    }

    private func dismissSneakPeek(for requestID: String) {
        guard let sneakPeekID = sneakPeekIDs.removeValue(forKey: requestID) else {
            return
        }

        bus?.emit(.dismissSneakPeek(requestID: sneakPeekID, target: .allScreens))
    }
}
