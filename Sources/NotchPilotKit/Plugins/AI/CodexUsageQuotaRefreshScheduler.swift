import Foundation

protocol CodexUsageQuotaRefreshScheduling: AnyObject {
    func activate(onRefreshRequested: @escaping @Sendable () -> Void)
    func setPollingEnabled(_ isEnabled: Bool)
    func deactivate()
}

final class CodexUsageQuotaRefreshScheduler: @unchecked Sendable, CodexUsageQuotaRefreshScheduling {
    private static let pollingRefreshInterval: TimeInterval = 30

    private let queue = DispatchQueue(label: "NotchPilot.CodexUsageQuotaRefreshScheduler", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private let pollingRefreshInterval: TimeInterval

    private var pollingTimer: DispatchSourceTimer?
    private var isPollingEnabled = false
    private var onRefreshRequested: (@Sendable () -> Void)?

    init(
        pollingRefreshInterval: TimeInterval = CodexUsageQuotaRefreshScheduler.pollingRefreshInterval
    ) {
        self.pollingRefreshInterval = pollingRefreshInterval
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopPollingTimer()
            onRefreshRequested = nil
        } else {
            queue.sync {
                stopPollingTimer()
                onRefreshRequested = nil
            }
        }
    }

    func activate(onRefreshRequested: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.onRefreshRequested = onRefreshRequested
            if self.isPollingEnabled {
                self.startPollingTimerIfNeeded()
            }
        }
    }

    func setPollingEnabled(_ isEnabled: Bool) {
        queue.async { [weak self] in
            guard let self, self.isPollingEnabled != isEnabled else {
                return
            }

            self.isPollingEnabled = isEnabled
            if isEnabled {
                self.startPollingTimerIfNeeded()
            } else {
                self.stopPollingTimer()
            }
        }
    }

    func deactivate() {
        queue.async { [weak self] in
            guard let self else { return }
            self.onRefreshRequested = nil
            self.isPollingEnabled = false
            self.stopPollingTimer()
        }
    }

    private func startPollingTimerIfNeeded() {
        guard pollingTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: pollingRefreshInterval
        )
        timer.setEventHandler { [weak self] in
            self?.emitRefreshRequest()
        }
        pollingTimer = timer
        timer.resume()
    }

    private func stopPollingTimer() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func emitRefreshRequest() {
        onRefreshRequested?()
    }
}
