import Combine
import Foundation
import SwiftUI

@MainActor
public final class CodexPlugin: AIPluginRendering {
    private enum SneakPeekKey {
        static let activity = "codex-activity"
    }

    public let id = "codex"
    public let title = "Codex"
    public let iconSystemName = "terminal"
    public let accentColor: Color = NotchPilotTheme.codex
    public let dockOrder = 110
    public let previewPriority: Int? = 90

    @Published public var isEnabled = true
    @Published public private(set) var sessions: [AISession] = []
    @Published public private(set) var pendingApprovals: [PendingApproval] = []
    @Published public private(set) var codexActionableSurface: CodexActionableSurface?
    @Published private(set) var usageQuotaSnapshot: AIUsageQuotaSnapshot?

    private static let codexThreadActivityExpiry: TimeInterval = 24 * 60 * 60
    private static let usageQuotaRefreshInterval: TimeInterval = 30

    private let settingsStore: SettingsStore
    private let codexMonitor: any CodexDesktopContextMonitoring & CodexDesktopActionableSurfaceMonitoring
    private let quotaReader: any CodexSessionQuotaReading
    private let quotaRefreshScheduler: any CodexUsageQuotaRefreshScheduling
    private let soundPlayer: any SoundPlaying
    private let nowProvider: @Sendable () -> Date
    private let sessionFocuser: any AISessionFocusing
    private let codexActionQueue = DispatchQueue(label: "NotchPilot.CodexPlugin.Actions", qos: .userInitiated)

    private weak var bus: EventBus?
    private var sneakPeekIDs: [String: UUID] = [:]
    private var codexThreads: CodexThreadRegistry
    private var rawCodexActionableSurface: CodexActionableSurface?
    private var settingsCancellables: Set<AnyCancellable> = []
    /// Tracks per-thread phase so we only fire `task.complete` on the
    /// edge of a transition into `.completed` (not every refresh).
    private var lastSeenPhasesByThreadID: [String: CodexThreadPhase] = [:]
    /// Tracks the last actionable surface id so we only fire
    /// `input.required` when a new surface appears (or replaces a different
    /// one), not on every nil → nil refresh.
    private var lastSeenSurfaceID: String?
    private var lastQuotaRefreshAt: Date?
    private var quotaRefreshTask: Task<Void, Never>?
    private var quotaRefreshGeneration: UInt64 = 0

    public convenience init(
        settingsStore: SettingsStore = .shared,
        codexMonitor: any CodexDesktopContextMonitoring & CodexDesktopActionableSurfaceMonitoring = CodexDesktopMonitor(),
        sessionFocuser: any AISessionFocusing = SystemAISessionFocuser(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            settingsStore: settingsStore,
            codexMonitor: codexMonitor,
            quotaReader: CodexSessionQuotaReader(),
            quotaRefreshScheduler: CodexSessionQuotaRefreshScheduler(),
            soundPlayer: SoundManager.shared,
            sessionFocuser: sessionFocuser,
            nowProvider: nowProvider
        )
    }

    init(
        settingsStore: SettingsStore = .shared,
        codexMonitor: any CodexDesktopContextMonitoring & CodexDesktopActionableSurfaceMonitoring = CodexDesktopMonitor(),
        quotaReader: any CodexSessionQuotaReading = CodexSessionQuotaReader(),
        quotaRefreshScheduler: any CodexUsageQuotaRefreshScheduling = CodexSessionQuotaRefreshScheduler(),
        soundPlayer: any SoundPlaying = SoundManager.shared,
        sessionFocuser: any AISessionFocusing = SystemAISessionFocuser(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.codexMonitor = codexMonitor
        self.quotaReader = quotaReader
        self.quotaRefreshScheduler = quotaRefreshScheduler
        self.soundPlayer = soundPlayer
        self.sessionFocuser = sessionFocuser
        self.nowProvider = nowProvider
        self.codexThreads = CodexThreadRegistry(activityExpiry: Self.codexThreadActivityExpiry)
        self.isEnabled = settingsStore.codexPluginEnabled

        settingsStore.$codexPluginEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.handlePluginEnabledChange(isEnabled)
            }
            .store(in: &settingsCancellables)

        settingsStore.$approvalSneakNotificationsEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handleApprovalSneakSettingChange(isEnabled: isEnabled)
            }
            .store(in: &settingsCancellables)

        settingsStore.$activitySneakPreviewsHidden
            .removeDuplicates()
            .sink { [weak self] isHidden in
                self?.handleActivitySneakSettingChange(isHidden: isHidden)
            }
            .store(in: &settingsCancellables)

        settingsStore.$interfaceLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.syncSneakPeek()
            }
            .store(in: &settingsCancellables)
    }

    public func activate(bus: EventBus) {
        guard isEnabled else {
            return
        }

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
        startQuotaRefreshScheduler()
        refreshUsageQuotaSnapshot(force: true)
        codexMonitor.start()
    }

    public func deactivate() {
        dismissAllSneakPeeks()
        quotaRefreshScheduler.deactivate()
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
        usageQuotaSnapshot = nil
        lastQuotaRefreshAt = nil
        cancelQuotaRefreshTask()
        lastSeenPhasesByThreadID.removeAll()
        lastSeenSurfaceID = nil
        bus = nil
    }

    public func preview(context: NotchContext) -> NotchPluginPreview? {
        guard isEnabled, shouldRenderCompactPreview else {
            return nil
        }
        guard let metrics = compactMetrics(context: context) else {
            return nil
        }
        let approvalNotice = approvalSneakNotice()
        let noticeLayout = AIPluginCompactApprovalNoticeLayout(
            notice: approvalNotice,
            baseTotalWidth: metrics.totalWidth
        )

        return NotchPluginPreview(
            width: noticeLayout.totalWidth,
            height: context.notchGeometry.compactSize.height + noticeLayout.height,
            view: AnyView(
                AIPluginCompactView(
                    plugin: self,
                    context: context,
                    approvalNotice: approvalNotice,
                    noticeLayout: noticeLayout
                )
            )
        )
    }

    var currentCompactActivity: AIPluginCompactActivity? {
        currentCompactActivity(
            approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
            activitySneakPreviewsHidden: activitySneakPreviewsHidden
        )
    }

    private func currentCompactActivity(
        approvalSneakNotificationsEnabled: Bool,
        activitySneakPreviewsHidden: Bool
    ) -> AIPluginCompactActivity? {
        guard isEnabled else {
            return nil
        }

        if approvalSneakNotificationsEnabled, let codexActionableSurface {
            return AIPluginCompactActivity(
                host: .codex,
                label: "Action Needed",
                inputTokenCount: preferredCodexSession(for: codexActionableSurface)?.inputTokenCount,
                outputTokenCount: preferredCodexSession(for: codexActionableSurface)?.outputTokenCount,
                approvalCount: 0,
                sessionTitle: preferredCodexTitle(for: codexActionableSurface),
                runtimeDurationText: runtimeDurationText(for: codexActionableSurface)
            )
        }

        guard activitySneakPreviewsHidden == false else {
            return nil
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
            sessionTitle: displayTitle(for: session),
            runtimeDurationText: runtimeDurationText(for: nil)
        )
    }

    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] {
        let now = nowProvider()
        return sessions
            .map { session in
                let codexSurface = codexSurfaceForSession(session)
                let context = codexThreads.preferredContext(for: session.id)
                return AIPluginExpandedSessionSummary(
                    id: session.id,
                    host: session.host,
                    title: expandedSessionTitle(for: session),
                    subtitle: codexSurface.map { _ in "Action Needed" } ?? session.activityLabel,
                    phase: expandedSessionPhase(for: session),
                    approvalCount: 0,
                    approvalRequestID: nil,
                    codexSurfaceID: codexSurface?.id,
                    updatedAt: session.updatedAt,
                    inputTokenCount: session.inputTokenCount,
                    outputTokenCount: session.outputTokenCount,
                    contextInputTokenCount: context?.contextInputTokenCount,
                    contextWindowTokenCount: context?.contextWindowTokenCount,
                    runtimeDurationText: runtimeDurationText(forThreadID: session.id, now: now)
                )
            }
            .sorted { lhs, rhs in
                if lhs.hasAttention != rhs.hasAttention {
                    return lhs.hasAttention
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    @discardableResult
    public func activateSession(id: String) -> Bool {
        guard isEnabled else {
            return false
        }

        let context = codexThreads.preferredContext(for: id)
        guard sessions.contains(where: { $0.id == id }) || context?.threadID == id else {
            return false
        }

        if codexMonitor.focusThread(id: id) {
            return true
        }

        let launchContext = sessions.first(where: { $0.id == id })?.launchContext
            ?? context?.launchContext
        return sessionFocuser.focusCodexThread(id: id, fallbackContext: launchContext)
    }

    @discardableResult
    public func stopSession(id: String) -> Bool {
        guard isEnabled, codexThreads.stop(threadID: id, at: nowProvider()) else {
            return false
        }

        if rawCodexActionableSurface?.threadID == id {
            let previousSurfaceID = rawCodexActionableSurface?.id
            rawCodexActionableSurface = nil
            if let previousSurfaceID {
                dismissSneakPeek(for: previousSurfaceID)
            }
        }

        lastSeenPhasesByThreadID[id] = .interrupted
        syncState()
        syncSneakPeek()
        return true
    }

    private func runtimeDurationText(forThreadID threadID: String, now: Date) -> String? {
        guard let duration = codexThreads.preferredActivityDuration(for: threadID, now: now) else {
            return nil
        }

        return AIRuntimeDurationFormatter.format(duration)
    }

    public func displayTitle(for session: AISession) -> String? {
        codexThreads.displayTitle(for: session)
    }

    public func preferredCodexTitle(for surface: CodexActionableSurface?) -> String? {
        codexThreads.preferredDisplayTitle(for: surface?.threadID)
    }

    private func expandedSessionPhase(for session: AISession) -> AIPluginSessionPhase {
        guard let context = codexThreads.preferredContext(for: session.id) else {
            return .unknown
        }

        return AIPluginSessionPhase(codexPhase: context.phase)
    }

    @discardableResult
    public func performCodexAction(_ action: CodexSurfaceAction, surfaceID: String) -> Bool {
        guard isEnabled,
              let currentSurface = rawCodexActionableSurface,
              currentSurface.id == surfaceID
        else {
            return false
        }

        rawCodexActionableSurface = nil
        syncState()
        dismissSneakPeek(for: currentSurface.id)

        let monitor = codexMonitor
        codexActionQueue.async {
            _ = monitor.perform(action: action, on: surfaceID)
        }
        return true
    }

    @discardableResult
    public func selectCodexOption(_ optionID: String, surfaceID: String) -> Bool {
        guard isEnabled,
              let currentSurface = rawCodexActionableSurface,
              currentSurface.id == surfaceID,
              currentSurface.options.contains(where: { $0.id == optionID })
        else {
            return false
        }

        optimisticallyUpdateCodexSurface(surfaceID: surfaceID) { surface in
            surface.selectingOption(optionID)
        }

        let monitor = codexMonitor
        codexActionQueue.async {
            _ = monitor.selectOption(optionID, on: surfaceID)
        }
        return true
    }

    @discardableResult
    public func updateCodexText(_ text: String, surfaceID: String) -> Bool {
        guard isEnabled,
              let currentSurface = rawCodexActionableSurface,
              currentSurface.id == surfaceID,
              currentSurface.textInput != nil
        else {
            return false
        }

        optimisticallyUpdateCodexSurface(surfaceID: surfaceID) { surface in
            surface.updatingText(text)
        }

        let monitor = codexMonitor
        codexActionQueue.async {
            _ = monitor.updateText(text, on: surfaceID)
        }
        return true
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
        let threadID = update.context.threadID
        let previousPhase = lastSeenPhasesByThreadID[threadID]
        let nextPhase = update.context.phase

        codexThreads.apply(update)
        syncState()
        syncSneakPeek()
        refreshUsageQuotaSnapshot(force: false)

        lastSeenPhasesByThreadID[threadID] = nextPhase
        if previousPhase != .completed, nextPhase == .completed {
            soundPlayer.play(.taskComplete)
        }
    }

    private func handleCodexConnectionStateChange(_ state: CodexDesktopConnectionState) {
        settingsStore.updateCodexDesktopConnection(state)
    }

    private func handleCodexSurfaceChange(_ surface: CodexActionableSurface?) {
        let previousSurfaceID = lastSeenSurfaceID
        let newSurfaceID = surface?.id

        rawCodexActionableSurface = surface
        syncState()
        syncSneakPeek()

        lastSeenSurfaceID = newSurfaceID
        if let newSurfaceID, newSurfaceID != previousSurfaceID {
            soundPlayer.play(.inputRequired)
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
        syncQuotaRefreshFallbackTimer()
    }

    var approvalSneakNotificationsEnabled: Bool {
        settingsStore.approvalSneakNotificationsEnabled
    }

    var activitySneakPreviewsHidden: Bool {
        settingsStore.activitySneakPreviewsHidden
    }

    private func mergedCodexSurface() -> CodexActionableSurface? {
        guard let rawCodexActionableSurface else {
            return nil
        }

        let context = codexThreads.preferredContext(for: rawCodexActionableSurface.threadID)
        return rawCodexActionableSurface.merged(with: context)
    }

    private func presentSneakPeek(for requestID: String, kind: SneakPeekRequestKind) {
        guard sneakPeekIDs[requestID] == nil else {
            return
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: SneakPeekRequestPriority.ai(for: kind),
            target: .activeScreen,
            kind: kind,
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

    private func dismissAllSneakPeeks() {
        for requestID in Array(sneakPeekIDs.keys) {
            dismissSneakPeek(for: requestID)
        }
    }

    private func syncSneakPeek() {
        syncSneakPeek(
            approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
            activitySneakPreviewsHidden: activitySneakPreviewsHidden
        )
    }

    private func syncSneakPeek(
        approvalSneakNotificationsEnabled: Bool,
        activitySneakPreviewsHidden: Bool
    ) {
        guard let desiredSneakPeek = desiredSneakPeek(
            approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
            activitySneakPreviewsHidden: activitySneakPreviewsHidden
        ) else {
            dismissAllSneakPeeks()
            return
        }

        for requestID in Array(sneakPeekIDs.keys) where requestID != desiredSneakPeek.key {
            dismissSneakPeek(for: requestID)
        }

        presentSneakPeek(for: desiredSneakPeek.key, kind: desiredSneakPeek.kind)
    }

    private var shouldRenderCompactPreview: Bool {
        shouldRenderCompactPreview(
            approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
            activitySneakPreviewsHidden: activitySneakPreviewsHidden
        )
    }

    private func shouldRenderCompactPreview(
        approvalSneakNotificationsEnabled: Bool,
        activitySneakPreviewsHidden: Bool
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        if approvalSneakNotificationsEnabled, codexActionableSurface != nil {
            return true
        }

        guard activitySneakPreviewsHidden == false else {
            return false
        }

        guard let context = codexThreads.preferredContext(for: nil) else {
            return false
        }

        switch context.phase {
        case .plan, .working:
            return true
        case .completed, .connected, .interrupted, .error, .unknown:
            return false
        }
    }

    private func handleApprovalSneakSettingChange(isEnabled: Bool) {
        objectWillChange.send()
        syncSneakPeek(
            approvalSneakNotificationsEnabled: isEnabled,
            activitySneakPreviewsHidden: activitySneakPreviewsHidden
        )
    }

    private func handleActivitySneakSettingChange(isHidden: Bool) {
        objectWillChange.send()
        syncSneakPeek(
            approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
            activitySneakPreviewsHidden: isHidden
        )
    }

    private func handlePluginEnabledChange(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        if isEnabled {
            if bus != nil {
                startQuotaRefreshScheduler()
            }
            refreshUsageQuotaSnapshot(force: true)
        } else {
            quotaRefreshScheduler.deactivate()
            usageQuotaSnapshot = nil
            lastQuotaRefreshAt = nil
            cancelQuotaRefreshTask()
        }
        syncSneakPeek()
        objectWillChange.send()
    }

    private func refreshUsageQuotaSnapshot(force: Bool, preferredFileURL: URL? = nil) {
        guard isEnabled else {
            usageQuotaSnapshot = nil
            lastQuotaRefreshAt = nil
            cancelQuotaRefreshTask()
            return
        }

        let now = nowProvider()
        if force == false,
           let lastQuotaRefreshAt,
           now.timeIntervalSince(lastQuotaRefreshAt) < Self.usageQuotaRefreshInterval {
            return
        }

        lastQuotaRefreshAt = now
        quotaRefreshGeneration &+= 1
        let generation = quotaRefreshGeneration
        let quotaReader = quotaReader
        quotaRefreshTask?.cancel()
        quotaRefreshTask = Task(priority: .utility) { [weak self] in
            let snapshot = await quotaReader.latestSnapshot(
                collectedAt: now,
                preferredFileURL: preferredFileURL
            )
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                guard let self,
                      self.quotaRefreshGeneration == generation,
                      self.isEnabled else {
                    return
                }

                self.usageQuotaSnapshot = snapshot
                self.quotaRefreshTask = nil
            }
        }
    }

    private func startQuotaRefreshScheduler() {
        quotaRefreshScheduler.activate { [weak self] preferredFileURL in
            Task { @MainActor [weak self] in
                self?.refreshUsageQuotaSnapshot(
                    force: false,
                    preferredFileURL: preferredFileURL
                )
            }
        }
        syncQuotaRefreshFallbackTimer()
    }

    private func syncQuotaRefreshFallbackTimer() {
        quotaRefreshScheduler.setFallbackTimerEnabled(isEnabled && codexThreads.hasLiveExecution)
    }

    private func cancelQuotaRefreshTask() {
        quotaRefreshGeneration &+= 1
        quotaRefreshTask?.cancel()
        quotaRefreshTask = nil
    }

    private func desiredSneakPeek(
        approvalSneakNotificationsEnabled: Bool,
        activitySneakPreviewsHidden: Bool
    ) -> (key: String, kind: SneakPeekRequestKind)? {
        guard isEnabled else {
            return nil
        }

        if approvalSneakNotificationsEnabled,
           let codexActionableSurface,
           currentCompactActivity(
               approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
               activitySneakPreviewsHidden: activitySneakPreviewsHidden
           ) != nil {
            return (codexActionableSurface.id, .attention)
        }

        guard
            shouldRenderCompactPreview(
                approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
                activitySneakPreviewsHidden: activitySneakPreviewsHidden
            ),
            currentCompactActivity(
                approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled,
                activitySneakPreviewsHidden: activitySneakPreviewsHidden
            ) != nil
        else {
            return nil
        }

        return (SneakPeekKey.activity, .activity)
    }

    private func runtimeDurationText(for surface: CodexActionableSurface?) -> String? {
        guard let duration = codexThreads.preferredActivityDuration(for: surface?.threadID, now: nowProvider()) else {
            return nil
        }

        return AIRuntimeDurationFormatter.format(duration)
    }
}
