import Combine
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

    private static let codexThreadActivityExpiry: TimeInterval = 24 * 60 * 60

    private let settingsStore: SettingsStore
    private let codexMonitor: any CodexDesktopContextMonitoring & CodexDesktopActionableSurfaceMonitoring
    private let nowProvider: @Sendable () -> Date

    private weak var bus: EventBus?
    private var sneakPeekIDs: [String: UUID] = [:]
    private var codexThreads: CodexThreadRegistry
    private var rawCodexActionableSurface: CodexActionableSurface?
    private var settingsCancellables: Set<AnyCancellable> = []

    public init(
        settingsStore: SettingsStore = .shared,
        codexMonitor: any CodexDesktopContextMonitoring & CodexDesktopActionableSurfaceMonitoring = CodexDesktopMonitor(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.codexMonitor = codexMonitor
        self.nowProvider = nowProvider
        self.codexThreads = CodexThreadRegistry(activityExpiry: Self.codexThreadActivityExpiry)

        settingsStore.$approvalSneakNotificationsEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handleApprovalSneakSettingChange(isEnabled: isEnabled)
            }
            .store(in: &settingsCancellables)
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
        dismissSneakPeek(for: SneakPeekKey.activity)
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

    public func preview(context: NotchContext) -> NotchPluginPreview? {
        guard shouldRenderCompactPreview else {
            return nil
        }
        guard let activity = currentCompactActivity else {
            return nil
        }

        let durationText = activity.runtimeDurationText ?? ""
        let approvalNotice = approvalSneakNotificationsEnabled
            ? AIPluginApprovalSneakNotice(pendingApprovals: pendingApprovals, codexSurface: codexActionableSurface)
            : nil
        let sideFrameWidth = max(
            compactPreviewLeftWidth(approvalCount: activity.approvalCount),
            compactPreviewTextWidth(durationText)
        )
        let totalHeight = context.notchGeometry.compactSize.height
            + (approvalNotice == nil ? 0 : CodexCompactPreviewLayout.approvalNoticeHeight)
        let totalWidth =
            10 * 2
            + context.notchGeometry.compactSize.width
            + sideFrameWidth * 2

        return NotchPluginPreview(
            width: totalWidth,
            height: totalHeight,
            view: AnyView(
                CodexCompactPreviewView(
                    iconSystemName: iconSystemName,
                    accentColor: accentColor,
                    durationText: durationText,
                    approvalCount: activity.approvalCount,
                    approvalNotice: approvalNotice,
                    sideFrameWidth: sideFrameWidth,
                    totalWidth: totalWidth,
                    totalHeight: totalHeight,
                    notchWidth: context.notchGeometry.compactSize.width,
                    notchHeight: context.notchGeometry.compactSize.height
                )
            )
        )
    }

    var currentCompactActivity: AIPluginCompactActivity? {
        currentCompactActivity(approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled)
    }

    private func currentCompactActivity(approvalSneakNotificationsEnabled: Bool) -> AIPluginCompactActivity? {
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
        sessions
            .map { session in
                let codexSurface = codexSurfaceForSession(session)
                return AIPluginExpandedSessionSummary(
                    id: session.id,
                    host: session.host,
                    title: expandedSessionTitle(for: session),
                    subtitle: codexSurface.map { _ in "Action Needed" } ?? session.activityLabel,
                    approvalCount: 0,
                    approvalRequestID: nil,
                    codexSurfaceID: codexSurface?.id,
                    updatedAt: session.updatedAt,
                    inputTokenCount: session.inputTokenCount,
                    outputTokenCount: session.outputTokenCount
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
        syncSneakPeek()
    }

    private func handleCodexConnectionStateChange(_ state: CodexDesktopConnectionState) {
        settingsStore.updateCodexDesktopConnection(state)
    }

    private func handleCodexSurfaceChange(_ surface: CodexActionableSurface?) {
        rawCodexActionableSurface = surface
        syncState()
        syncSneakPeek()
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

    var approvalSneakNotificationsEnabled: Bool {
        settingsStore.approvalSneakNotificationsEnabled
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

    private func syncSneakPeek() {
        syncSneakPeek(approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled)
    }

    private func syncSneakPeek(approvalSneakNotificationsEnabled: Bool) {
        guard
            shouldRenderCompactPreview(approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled),
            currentCompactActivity(approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled) != nil
        else {
            dismissSneakPeek(for: SneakPeekKey.activity)
            return
        }

        presentSneakPeek(for: SneakPeekKey.activity)
    }

    private var shouldRenderCompactPreview: Bool {
        shouldRenderCompactPreview(approvalSneakNotificationsEnabled: approvalSneakNotificationsEnabled)
    }

    private func shouldRenderCompactPreview(approvalSneakNotificationsEnabled: Bool) -> Bool {
        if approvalSneakNotificationsEnabled, codexActionableSurface != nil {
            return true
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
        syncSneakPeek(approvalSneakNotificationsEnabled: isEnabled)
    }

    private func runtimeDurationText(for surface: CodexActionableSurface?) -> String? {
        guard let duration = codexThreads.preferredActivityDuration(for: surface?.threadID, now: nowProvider()) else {
            return nil
        }

        return formatRuntimeDuration(duration)
    }

    private func formatRuntimeDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))m"
        }
        if minutes > 0 {
            return "\(minutes)m\(String(format: "%02d", seconds))s"
        }
        return "\(seconds)s"
    }

    private func compactPreviewTextWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width) + 2
    }

    private func compactPreviewLeftWidth(approvalCount: Int) -> CGFloat {
        guard approvalCount > 0 else {
            return 34
        }

        return 22 + 5 + compactPreviewTextWidth("\(approvalCount)") + 10
    }
}

private enum CodexCompactPreviewLayout {
    static let approvalNoticeHeight: CGFloat = 32
}

private struct CodexCompactPreviewView: View {
    let iconSystemName: String
    let accentColor: Color
    let durationText: String
    let approvalCount: Int
    let approvalNotice: AIPluginApprovalSneakNotice?
    let sideFrameWidth: CGFloat
    let totalWidth: CGFloat
    let totalHeight: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                brandCluster
                    .frame(width: sideFrameWidth, alignment: .leading)

                Spacer(minLength: notchWidth)

                Text(durationText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                    .lineLimit(1)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: sideFrameWidth, alignment: .trailing)
            }
            .frame(height: notchHeight, alignment: .center)

            if let approvalNotice {
                approvalNoticeRow(approvalNotice)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: totalWidth, height: totalHeight, alignment: .top)
    }

    private var brandCluster: some View {
        HStack(spacing: 5) {
            if let glyph = NotchPilotBrandGlyph(systemName: iconSystemName) {
                NotchPilotBrandIcon(glyph: glyph, size: 22)
            } else {
                NotchPilotIconTile(
                    systemName: iconSystemName,
                    accent: accentColor,
                    size: 34,
                    isActive: true
                )
            }

            if approvalCount > 0 {
                NotchPilotStatusBadge(
                    text: "\(approvalCount)",
                    color: accentColor,
                    foreground: .white
                )
            }
        }
    }

    private func approvalNoticeRow(_ notice: AIPluginApprovalSneakNotice) -> some View {
        Text(notice.text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: CodexCompactPreviewLayout.approvalNoticeHeight, alignment: .center)
    }
}
