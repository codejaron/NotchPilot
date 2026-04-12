import Combine
import SwiftUI

private actor SystemMonitorSamplerWorker {
    private let sampler: any SystemMonitorSampling

    init(sampler: any SystemMonitorSampling) {
        self.sampler = sampler
    }

    func snapshot() -> SystemMonitorSnapshot {
        sampler.snapshot()
    }
}

@MainActor
public final class SystemMonitorPlugin: NotchPlugin {
    private enum SneakPreviewRequest {
        static let priority = 2_000
    }

    public let id = "system-monitor"
    public let title = "System"
    public let iconSystemName = "speedometer"
    public let accentColor = Color(red: 0.36, green: 0.82, blue: 1.0)
    public let dockOrder = 90
    public let previewPriority: Int? = 300

    @Published public var isEnabled = true
    @Published private(set) var snapshot: SystemMonitorSnapshot
    @Published private(set) var sneakConfiguration: SystemMonitorSneakConfiguration

    private let samplerWorker: SystemMonitorSamplerWorker
    private let settingsStore: SettingsStore
    private var refreshCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var settingsCancellables: Set<AnyCancellable> = []
    private weak var bus: EventBus?
    private var sneakPeekRequestID: UUID?

    public convenience init() {
        self.init(sampler: SystemMonitorDefaultSampler())
    }

    init(
        sampler: any SystemMonitorSampling,
        settingsStore: SettingsStore = .shared,
        sneakConfiguration: SystemMonitorSneakConfiguration? = nil
    ) {
        self.samplerWorker = SystemMonitorSamplerWorker(sampler: sampler)
        self.settingsStore = settingsStore
        self.sneakConfiguration = sneakConfiguration ?? settingsStore.systemMonitorSneakConfiguration
        self.snapshot = .unavailable

        if sneakConfiguration == nil {
            settingsStore.$systemMonitorSneakConfiguration
                .removeDuplicates()
                .sink { [weak self] configuration in
                    self?.sneakConfiguration = configuration
                }
                .store(in: &settingsCancellables)
        }

        settingsStore.$systemMonitorSneakPreviewEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncSneakPeekRequest()
            }
            .store(in: &settingsCancellables)
    }

    public func preview(context: NotchContext) -> NotchPluginPreview? {
        let sideFrameWidth = SystemMonitorSneakPreviewLayout.sideFrameWidth(
            snapshot: snapshot,
            configuration: sneakConfiguration
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
                    configuration: sneakConfiguration,
                    context: context,
                    sideFrameWidth: sideFrameWidth,
                    totalWidth: width
                )
            )
        )
    }

    public func contentView(context: NotchContext) -> AnyView {
        AnyView(SystemMonitorDashboardView(snapshot: snapshot, accentColor: accentColor))
    }

    public func activate(bus: EventBus) {
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
    }

    func refresh() async {
        let latestSnapshot = await samplerWorker.snapshot()
        guard Task.isCancelled == false else {
            return
        }
        snapshot = latestSnapshot
    }

    private func scheduleRefresh() {
        guard refreshTask == nil else {
            return
        }

        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            await self?.completeScheduledRefresh(generation: generation)
        }
    }

    private func completeScheduledRefresh(generation: UInt64) async {
        let latestSnapshot = await samplerWorker.snapshot()
        let wasCancelled = Task.isCancelled

        guard refreshGeneration == generation else {
            return
        }

        refreshTask = nil
        guard wasCancelled == false else {
            return
        }
        snapshot = latestSnapshot
    }

    private func syncSneakPeekRequest() {
        guard settingsStore.systemMonitorSneakPreviewEnabled else {
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
}
