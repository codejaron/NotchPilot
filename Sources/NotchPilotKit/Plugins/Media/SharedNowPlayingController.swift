import Combine
import Foundation

@MainActor
final class SharedNowPlayingController: ObservableObject, NowPlayingSessionMonitoring {
    @Published private(set) var currentState: MediaPlaybackState

    var statePublisher: AnyPublisher<MediaPlaybackState, Never> {
        $currentState.eraseToAnyPublisher()
    }

    private let monitor: any NowPlayingSessionMonitoring
    private var monitorCancellable: AnyCancellable?
    private var isStarted = false
    private var startRequestCount = 0

    init(monitor: any NowPlayingSessionMonitoring = NowPlayingSessionMonitor()) {
        self.monitor = monitor
        self.currentState = monitor.currentState
    }

    func start() {
        startRequestCount += 1
        guard isStarted == false else {
            handleMonitorStateChange(monitor.currentState)
            return
        }
        isStarted = true
        monitorCancellable = monitor.statePublisher.sink { [weak self] state in
            self?.handleMonitorStateChange(state)
        }
        monitor.start()
        handleMonitorStateChange(monitor.currentState)
    }

    func stop() {
        guard startRequestCount > 0 else {
            return
        }
        startRequestCount -= 1
        guard startRequestCount == 0, isStarted else {
            return
        }
        isStarted = false
        monitorCancellable = nil
        monitor.stop()
    }

    func play() {
        monitor.play()
    }

    func pause() {
        monitor.pause()
    }

    func playPause() {
        monitor.playPause()
    }

    func nextTrack() {
        monitor.nextTrack()
    }

    func previousTrack() {
        monitor.previousTrack()
    }

    func seek(to time: Double) {
        monitor.seek(to: time)
    }

    func currentPlaybackTime(for source: MediaPlaybackSource) async -> TimeInterval? {
        await monitor.currentPlaybackTime(for: source)
    }

    private func handleMonitorStateChange(_ state: MediaPlaybackState) {
        currentState = state
    }
}
