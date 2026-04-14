import Combine
import SwiftUI

@MainActor
public final class MediaPlaybackPlugin: NotchPlugin {
    private enum SneakPreviewRequest {
        static let priority = 700
        static let pausedAutoDismiss: TimeInterval = 10
    }

    public let id = "media-playback"
    public let title = "Media"
    public let iconSystemName = "play.circle.fill"
    public let accentColor = NotchPilotTheme.mediaPlayback
    public let dockOrder = 120
    public let previewPriority: Int? = 200

    @Published public var isEnabled: Bool
    @Published private(set) var playbackState: MediaPlaybackState

    private let monitor: any NowPlayingSessionMonitoring
    private let settingsStore: SettingsStore
    private weak var bus: EventBus?
    private var sneakPeekRequestID: UUID?
    private var presentedAutoDismissAfter: TimeInterval?
    private var settingsCancellables: Set<AnyCancellable> = []

    init(
        monitor: any NowPlayingSessionMonitoring = NowPlayingSessionMonitor(),
        settingsStore: SettingsStore = .shared
    ) {
        self.monitor = monitor
        self.settingsStore = settingsStore
        self.isEnabled = settingsStore.mediaPlaybackEnabled
        self.playbackState = monitor.currentState

        settingsStore.$mediaPlaybackEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handlePluginEnabledChange(isEnabled)
            }
            .store(in: &settingsCancellables)

        settingsStore.$mediaPlaybackSneakPreviewEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncSneakPeek()
                self?.objectWillChange.send()
            }
            .store(in: &settingsCancellables)
    }

    public func preview(context: NotchContext) -> NotchPluginPreview? {
        guard isEnabled, settingsStore.mediaPlaybackSneakPreviewEnabled else {
            return nil
        }
        guard case let .active(snapshot) = playbackState else {
            return nil
        }

        let totalWidth = context.notchGeometry.compactSize.width + 126
        return NotchPluginPreview(
            width: totalWidth,
            height: context.notchGeometry.compactSize.height,
            view: AnyView(
                MediaPlaybackCompactPreviewView(
                    snapshot: snapshot,
                    totalWidth: totalWidth,
                    notchHeight: context.notchGeometry.compactSize.height
                )
            )
        )
    }

    public func contentView(context: NotchContext) -> AnyView {
        AnyView(
            MediaPlaybackExpandedView(
                state: isEnabled ? playbackState : .idle,
                accentColor: accentColor,
                onPrevious: { [weak self] in self?.monitor.previousTrack() },
                onPlayPause: { [weak self] in self?.performPrimaryPlaybackAction() },
                onNext: { [weak self] in self?.monitor.nextTrack() },
                onSeek: { [weak self] time in self?.monitor.seek(to: time) }
            )
        )
    }

    public func activate(bus: EventBus) {
        self.bus = bus
        monitor.onStateChange = { [weak self] state in
            self?.handleMonitorStateChange(state)
        }
        monitor.start()
        handleMonitorStateChange(monitor.currentState)
    }

    public func deactivate() {
        monitor.onStateChange = nil
        monitor.stop()
        dismissSneakPeek()
        bus = nil
        playbackState = .idle
    }

    private func handleMonitorStateChange(_ state: MediaPlaybackState) {
        playbackState = state
        syncSneakPeek()
        objectWillChange.send()
    }

    private func handlePluginEnabledChange(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        syncSneakPeek()
        objectWillChange.send()
    }

    private func syncSneakPeek() {
        guard isEnabled, settingsStore.mediaPlaybackSneakPreviewEnabled else {
            dismissSneakPeek()
            return
        }

        guard case let .active(snapshot) = playbackState else {
            dismissSneakPeek()
            return
        }

        let autoDismissAfter = snapshot.isPlaying ? nil : SneakPreviewRequest.pausedAutoDismiss

        guard sneakPeekRequestID == nil || presentedAutoDismissAfter != autoDismissAfter else {
            return
        }

        dismissSneakPeek()
        presentSneakPeek(autoDismissAfter: autoDismissAfter)
    }

    private func presentSneakPeek(autoDismissAfter: TimeInterval?) {
        guard let bus else {
            return
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: SneakPreviewRequest.priority,
            target: .activeScreen,
            isInteractive: false,
            autoDismissAfter: autoDismissAfter
        )
        sneakPeekRequestID = request.id
        presentedAutoDismissAfter = autoDismissAfter
        bus.emit(.sneakPeekRequested(request))
    }

    private func dismissSneakPeek() {
        guard let requestID = sneakPeekRequestID else {
            presentedAutoDismissAfter = nil
            return
        }

        bus?.emit(.dismissSneakPeek(requestID: requestID, target: .allScreens))
        sneakPeekRequestID = nil
        presentedAutoDismissAfter = nil
    }

    func performPrimaryPlaybackActionForTesting() {
        performPrimaryPlaybackAction()
    }

    private func performPrimaryPlaybackAction() {
        guard case let .active(snapshot) = playbackState else {
            monitor.playPause()
            return
        }

        if snapshot.isPlaying {
            monitor.pause()
        } else {
            monitor.play()
        }
    }
}
