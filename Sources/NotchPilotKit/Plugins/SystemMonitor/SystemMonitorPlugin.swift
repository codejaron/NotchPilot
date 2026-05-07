import Combine
import SwiftUI

private actor SystemMonitorSamplerWorker {
    private let sampler: any SystemMonitorSampling

    init(sampler: any SystemMonitorSampling) {
        self.sampler = sampler
    }

    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot {
        sampler.snapshot(demand: demand)
    }
}

@MainActor
public final class SystemMonitorPlugin: NotchPlugin {
    private enum SneakPreviewRequest {
        static let priority = SneakPeekRequestPriority.systemMonitor
    }

    public let id = "system-monitor"
    public let title = "System"
    public let iconSystemName = "cpu"
    public let accentColor = Color(red: 0.36, green: 0.82, blue: 1.0)
    public let dockOrder = 90
    public let previewPriority: Int? = 300

    @Published public var isEnabled = true
    @Published private(set) var snapshot: SystemMonitorSnapshot
    @Published private(set) var sneakConfiguration: SystemMonitorSneakConfiguration
    @Published private(set) var activeAlerts: [SystemMonitorMetric: SystemMonitorActiveAlert] = [:]

    private let samplerWorker: SystemMonitorSamplerWorker
    private let settingsStore: SettingsStore
    private let alertEngine: SystemMonitorAlertEngine
    private var refreshCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var settingsCancellables: Set<AnyCancellable> = []
    private weak var bus: EventBus?
    private var sneakPeekRequestID: UUID?
    private var dashboardMountCount: Int = 0

    public convenience init() {
        self.init(sampler: SystemMonitorDefaultSampler())
    }

    init(
        sampler: any SystemMonitorSampling,
        settingsStore: SettingsStore = .shared,
        sneakConfiguration: SystemMonitorSneakConfiguration? = nil,
        alertEngine: SystemMonitorAlertEngine? = nil
    ) {
        self.samplerWorker = SystemMonitorSamplerWorker(sampler: sampler)
        self.settingsStore = settingsStore
        self.sneakConfiguration = sneakConfiguration ?? settingsStore.systemMonitorSneakConfiguration
        let engine = alertEngine ?? SystemMonitorAlertEngine(
            rules: SystemMonitorAlertRuleCatalog.rules(for: settingsStore.systemMonitorAlertThresholds)
        )
        self.alertEngine = engine
        self.snapshot = .unavailable
        self.isEnabled = settingsStore.systemMonitorEnabled

        settingsStore.$systemMonitorAlertThresholds
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] thresholds in
                self?.handleAlertThresholdsChange(thresholds)
            }
            .store(in: &settingsCancellables)

        settingsStore.$systemMonitorEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handlePluginEnabledChange(isEnabled)
            }
            .store(in: &settingsCancellables)

        if sneakConfiguration == nil {
            settingsStore.$systemMonitorSneakConfiguration
                .removeDuplicates()
                .sink { [weak self] configuration in
                    self?.handleSneakConfigurationChange(configuration)
                }
                .store(in: &settingsCancellables)
        }

        settingsStore.$systemMonitorSneakPreviewEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.syncSneakPeekRequest(systemMonitorSneakPreviewEnabled: isEnabled)
            }
            .store(in: &settingsCancellables)

        settingsStore.$activitySneakPreviewsHidden
            .removeDuplicates()
            .sink { [weak self] isHidden in
                self?.syncSneakPeekRequest(activitySneakPreviewsHidden: isHidden)
            }
            .store(in: &settingsCancellables)

        settingsStore.$interfaceLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &settingsCancellables)
    }

    public func preview(context: NotchContext) -> NotchPluginPreview? {
        guard isEnabled,
              settingsStore.systemMonitorSneakPreviewEnabled,
              settingsStore.activitySneakPreviewsHidden == false
        else {
            return nil
        }

        let effectiveConfiguration = composeEffectiveConfiguration()
        guard hasContentToShow(in: effectiveConfiguration) else {
            return nil
        }

        let sideFrameWidth = SystemMonitorSneakPreviewLayout.sideFrameWidth(
            snapshot: snapshot,
            configuration: effectiveConfiguration,
            language: settingsStore.interfaceLanguage
        )
        let width = SystemMonitorSneakPreviewLayout.totalWidth(
            compactNotchWidth: context.notchGeometry.compactSize.width,
            sideFrameWidth: sideFrameWidth
        )

        return NotchPluginPreview(
            width: width,
            height: context.notchGeometry.compactSize.height,
            view: AnyView(
                SystemMonitorSneakPreviewView(
                    snapshot: snapshot,
                    configuration: effectiveConfiguration,
                    activeAlerts: activeAlerts,
                    context: context,
                    sideFrameWidth: sideFrameWidth,
                    totalWidth: width
                )
            )
        )
    }

    public func contentView(context: NotchContext) -> AnyView {
        AnyView(SystemMonitorDashboardView(plugin: self, accentColor: accentColor))
    }

    func dashboardDidAppear() {
        dashboardMountCount += 1
    }

    func dashboardDidDisappear() {
        dashboardMountCount = max(0, dashboardMountCount - 1)
    }

    private func currentSamplingDemand() -> SystemMonitorSamplingDemand {
        let needsDetailed = sneakPeekRequestID != nil || dashboardMountCount > 0
        return needsDetailed ? .detailed : .basic
    }

    public func activate(bus: EventBus) {
        guard isEnabled else {
            return
        }

        self.bus = bus
        scheduleRefresh()
        syncSneakPeekRequest()
        refreshCancellable?.cancel()
        refreshCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
    }

    public func deactivate() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshCancellable?.cancel()
        refreshCancellable = nil
        dismissSneakPeekRequest()
        bus = nil
        snapshot = .unavailable
        alertEngine.reset()
        activeAlerts = [:]
    }

    func refresh() async {
        let demand = currentSamplingDemand()
        let latestSnapshot = await samplerWorker.snapshot(demand: demand)
        guard Task.isCancelled == false else {
            return
        }
        applySnapshot(latestSnapshot)
    }

    private func scheduleRefresh() {
        guard refreshTask == nil else {
            return
        }

        let generation = refreshGeneration
        let demand = currentSamplingDemand()
        refreshTask = Task { [weak self] in
            await self?.completeScheduledRefresh(generation: generation, demand: demand)
        }
    }

    private func completeScheduledRefresh(generation: UInt64, demand: SystemMonitorSamplingDemand) async {
        let latestSnapshot = await samplerWorker.snapshot(demand: demand)
        let wasCancelled = Task.isCancelled

        guard refreshGeneration == generation else {
            return
        }

        refreshTask = nil
        guard wasCancelled == false else {
            return
        }
        applySnapshot(latestSnapshot)
    }

    private func applySnapshot(_ snapshot: SystemMonitorSnapshot) {
        self.snapshot = snapshot
        _ = alertEngine.process(snapshot: snapshot)
        let updatedAlerts = alertEngine.currentAlerts
        if activeAlerts != updatedAlerts {
            activeAlerts = updatedAlerts
        }
        syncSneakPeekRequest()
    }

    private func handleSneakConfigurationChange(_ configuration: SystemMonitorSneakConfiguration) {
        sneakConfiguration = configuration
        syncSneakPeekRequest()
    }

    private func syncSneakPeekRequest(
        systemMonitorSneakPreviewEnabled: Bool? = nil,
        activitySneakPreviewsHidden: Bool? = nil
    ) {
        let isSystemMonitorSneakEnabled =
            systemMonitorSneakPreviewEnabled ?? settingsStore.systemMonitorSneakPreviewEnabled
        let areActivitySneaksHidden =
            activitySneakPreviewsHidden ?? settingsStore.activitySneakPreviewsHidden

        let shouldDisplay = isEnabled
            && isSystemMonitorSneakEnabled
            && areActivitySneaksHidden == false
            && hasContentToShow(in: composeEffectiveConfiguration())

        guard shouldDisplay else {
            dismissSneakPeekRequest()
            return
        }

        guard sneakPeekRequestID == nil, let bus else {
            return
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: SneakPreviewRequest.priority,
            target: .allScreens,
            isInteractive: false,
            autoDismissAfter: nil
        )
        sneakPeekRequestID = request.id
        bus.emit(.sneakPeekRequested(request))
    }

    private func dismissSneakPeekRequest() {
        guard let requestID = sneakPeekRequestID else {
            return
        }

        bus?.emit(.dismissSneakPeek(requestID: requestID, target: .allScreens))
        sneakPeekRequestID = nil
    }

    private func handlePluginEnabledChange(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        if isEnabled == false {
            alertEngine.reset()
            activeAlerts = [:]
        }
        syncSneakPeekRequest()
        objectWillChange.send()
    }

    private func handleAlertThresholdsChange(_ thresholds: SystemMonitorAlertThresholds) {
        alertEngine.updateRules(SystemMonitorAlertRuleCatalog.rules(for: thresholds))
        // Re-run the engine against the latest snapshot so the new thresholds
        // take effect immediately instead of waiting for the next sampler tick.
        applySnapshot(snapshot)
    }

    private func composeEffectiveConfiguration() -> SystemMonitorSneakConfiguration {
        SystemMonitorSneakComposer.compose(
            base: sneakConfiguration,
            activeAlerts: activeAlerts
        )
    }

    private func hasContentToShow(in configuration: SystemMonitorSneakConfiguration) -> Bool {
        configuration.leftMetrics.isEmpty == false || configuration.rightMetrics.isEmpty == false
    }
}

enum SystemMonitorSneakComposer {
    static func compose(
        base: SystemMonitorSneakConfiguration,
        activeAlerts: [SystemMonitorMetric: SystemMonitorActiveAlert]
    ) -> SystemMonitorSneakConfiguration {
        let limit = SystemMonitorSneakConfiguration.defaultLimit

        switch base.mode {
        case .alwaysOn:
            return base

        case .pinnedReactive:
            let reactiveOrder = orderedReactiveMetrics(base: base, activeAlerts: activeAlerts)
            guard reactiveOrder.isEmpty == false else {
                return base
            }
            // Reactive metrics take priority over pinned right slots; if the
            // user pins more than one metric on the right, the surplus is
            // dropped to keep the sneak compact.
            let mergedRight = reactiveOrder + base.rightMetrics
            return SystemMonitorSneakConfiguration(
                mode: base.mode,
                left: base.leftMetrics,
                right: deduplicateMetrics(mergedRight, limit: limit),
                reactive: base.reactiveMetrics,
                limit: limit
            )

        case .ambient:
            let reactiveOrder = orderedReactiveMetrics(base: base, activeAlerts: activeAlerts)
            guard reactiveOrder.isEmpty == false else {
                return SystemMonitorSneakConfiguration(
                    mode: base.mode,
                    left: [],
                    right: [],
                    reactive: base.reactiveMetrics,
                    limit: limit
                )
            }
            let leftSlice = Array(reactiveOrder.prefix(limit))
            let rightSlice = Array(reactiveOrder.dropFirst(limit).prefix(limit))
            return SystemMonitorSneakConfiguration(
                mode: base.mode,
                left: leftSlice,
                right: rightSlice,
                reactive: base.reactiveMetrics,
                limit: limit
            )
        }
    }

    private static func orderedReactiveMetrics(
        base: SystemMonitorSneakConfiguration,
        activeAlerts: [SystemMonitorMetric: SystemMonitorActiveAlert]
    ) -> [SystemMonitorMetric] {
        let allowed = base.reactiveMetrics
        return allowed.compactMap { metric -> (SystemMonitorMetric, SystemMonitorAlertSeverity, Date)? in
            guard let alert = activeAlerts[metric] else { return nil }
            return (metric, alert.severity, alert.firedAt)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            if lhs.2 != rhs.2 {
                return lhs.2 < rhs.2
            }
            let lhsIndex = allowed.firstIndex(of: lhs.0) ?? Int.max
            let rhsIndex = allowed.firstIndex(of: rhs.0) ?? Int.max
            return lhsIndex < rhsIndex
        }
        .map(\.0)
    }

    private static func deduplicateMetrics(
        _ metrics: [SystemMonitorMetric],
        limit: Int
    ) -> [SystemMonitorMetric] {
        var seen: Set<SystemMonitorMetric> = []
        var result: [SystemMonitorMetric] = []
        for metric in metrics {
            guard seen.insert(metric).inserted else { continue }
            result.append(metric)
            if result.count >= limit { break }
        }
        return result
    }
}
