import Combine
import SwiftUI

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

    private let sampler: any SystemMonitorSampling
    private let settingsStore: SettingsStore
    private var refreshCancellable: AnyCancellable?
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
        self.sampler = sampler
        self.settingsStore = settingsStore
        self.sneakConfiguration = sneakConfiguration ?? settingsStore.systemMonitorSneakConfiguration
        self.snapshot = sampler.snapshot()

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
        refresh()
        syncSneakPeekRequest()
        refreshCancellable?.cancel()
        refreshCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    public func deactivate() {
        refreshCancellable?.cancel()
        refreshCancellable = nil
        dismissSneakPeekRequest()
        bus = nil
        snapshot = .unavailable
    }

    func refresh() {
        snapshot = sampler.snapshot()
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
