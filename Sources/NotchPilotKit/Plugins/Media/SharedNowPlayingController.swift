import Combine
import Foundation

@MainActor
final class SharedNowPlayingController: ObservableObject, NowPlayingSessionMonitoring {
    @Published private(set) var currentState: MediaPlaybackState

    var onStateChange: (@MainActor (MediaPlaybackState) -> Void)?

    private let monitor: any NowPlayingSessionMonitoring
    private var isStarted = false

    init(monitor: any NowPlayingSessionMonitoring = NowPlayingSessionMonitor()) {
        self.monitor = monitor
        self.currentState = monitor.currentState
    }

    func start() {
        guard isStarted == false else {
            handleMonitorStateChange(monitor.currentState)
            return
        }
        isStarted = true
        monitor.onStateChange = { [weak self] state in
            self?.handleMonitorStateChange(state)
        }
        monitor.start()
        handleMonitorStateChange(monitor.currentState)
    }

    func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        monitor.onStateChange = nil
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

    private func handleMonitorStateChange(_ state: MediaPlaybackState) {
        currentState = state
        onStateChange?(state)
        objectWillChange.send()
    }
}
