import CoreServices
import Foundation

protocol CodexUsageQuotaRefreshScheduling: AnyObject {
    func activate(onRefreshRequested: @escaping @Sendable (URL?) -> Void)
    func setFallbackTimerEnabled(_ isEnabled: Bool)
    func deactivate()
}

final class CodexSessionQuotaRefreshScheduler: @unchecked Sendable, CodexUsageQuotaRefreshScheduling {
    private static let fileEventLatency: TimeInterval = 0.5
    private static let fileEventDebounceInterval: TimeInterval = 0.75
    private static let fallbackRefreshInterval: TimeInterval = 60

    private let sessionsDirectoryURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "NotchPilot.CodexSessionQuotaRefreshScheduler", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private let fileEventLatency: TimeInterval
    private let fileEventDebounceInterval: TimeInterval
    private let fallbackRefreshInterval: TimeInterval

    private var eventStream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var fallbackTimer: DispatchSourceTimer?
    private var isFallbackTimerEnabled = false
    private var pendingChangedFileURL: URL?
    private var onRefreshRequested: (@Sendable (URL?) -> Void)?

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        fileEventLatency: TimeInterval = CodexSessionQuotaRefreshScheduler.fileEventLatency,
        fileEventDebounceInterval: TimeInterval = CodexSessionQuotaRefreshScheduler.fileEventDebounceInterval,
        fallbackRefreshInterval: TimeInterval = CodexSessionQuotaRefreshScheduler.fallbackRefreshInterval
    ) {
        self.sessionsDirectoryURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        self.fileManager = fileManager
        self.fileEventLatency = fileEventLatency
        self.fileEventDebounceInterval = fileEventDebounceInterval
        self.fallbackRefreshInterval = fallbackRefreshInterval
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopFileEventStream()
            stopFallbackTimer()
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            onRefreshRequested = nil
        } else {
            queue.sync {
                stopFileEventStream()
                stopFallbackTimer()
                debounceWorkItem?.cancel()
                debounceWorkItem = nil
                onRefreshRequested = nil
            }
        }
    }

    func activate(onRefreshRequested: @escaping @Sendable (URL?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.onRefreshRequested = onRefreshRequested
            self.startFileEventStreamIfNeeded()
        }
    }

    func setFallbackTimerEnabled(_ isEnabled: Bool) {
        queue.async { [weak self] in
            guard let self, self.isFallbackTimerEnabled != isEnabled else {
                return
            }

            self.isFallbackTimerEnabled = isEnabled
            if isEnabled {
                self.startFallbackTimerIfNeeded()
            } else {
                self.stopFallbackTimer()
            }
        }
    }

    func deactivate() {
        queue.async { [weak self] in
            guard let self else { return }
            self.onRefreshRequested = nil
            self.isFallbackTimerEnabled = false
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.pendingChangedFileURL = nil
            self.stopFallbackTimer()
            self.stopFileEventStream()
        }
    }

    private func startFileEventStreamIfNeeded() {
        guard eventStream == nil,
              fileManager.fileExists(atPath: sessionsDirectoryURL.path)
        else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.handleFileEvents,
            &context,
            [sessionsDirectoryURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            fileEventLatency,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        eventStream = stream
    }

    private func stopFileEventStream() {
        guard let eventStream else {
            return
        }

        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
    }

    private func startFallbackTimerIfNeeded() {
        guard fallbackTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + fallbackRefreshInterval,
            repeating: fallbackRefreshInterval
        )
        timer.setEventHandler { [weak self] in
            self?.startFileEventStreamIfNeeded()
            self?.emitRefreshRequest(preferredFileURL: nil)
        }
        fallbackTimer = timer
        timer.resume()
    }

    private func stopFallbackTimer() {
        fallbackTimer?.cancel()
        fallbackTimer = nil
    }

    private func scheduleDebouncedRefresh(preferredFileURL: URL?) {
        if let preferredFileURL {
            pendingChangedFileURL = preferredFileURL
        }
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let preferredFileURL = self.pendingChangedFileURL
            self.pendingChangedFileURL = nil
            self.emitRefreshRequest(preferredFileURL: preferredFileURL)
        }
        debounceWorkItem = workItem
        queue.asyncAfter(
            deadline: .now() + fileEventDebounceInterval,
            execute: workItem
        )
    }

    private func emitRefreshRequest(preferredFileURL: URL?) {
        onRefreshRequested?(preferredFileURL)
    }

    private static let handleFileEvents: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
        guard let info else {
            return
        }

        let scheduler = Unmanaged<CodexSessionQuotaRefreshScheduler>
            .fromOpaque(info)
            .takeUnretainedValue()
        scheduler.scheduleDebouncedRefresh(preferredFileURL: changedSessionFileURL(from: eventPaths))
    }

    private static func changedSessionFileURL(from eventPaths: UnsafeMutableRawPointer) -> URL? {
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .first { $0.pathExtension == "jsonl" }
    }
}
