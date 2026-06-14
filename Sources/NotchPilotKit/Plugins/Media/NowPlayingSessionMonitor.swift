import Darwin
import Combine
import Foundation

private enum MediaRemoteAdapterCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

private protocol MediaRemoteCommandControlling {
    func play()
    func pause()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
    func seek(to time: Double)
}

private final class SystemMediaRemoteCommandController: MediaRemoteCommandControlling {
    private let sendCommand: @convention(c) (Int, AnyObject?) -> Void
    private let setElapsedTime: @convention(c) (Double) -> Void

    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
            ),
            let sendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteSendCommand" as CFString
            ),
            let setElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteSetElapsedTime" as CFString
            )
        else {
            return nil
        }

        sendCommand = unsafeBitCast(
            sendCommandPointer,
            to: (@convention(c) (Int, AnyObject?) -> Void).self
        )
        setElapsedTime = unsafeBitCast(
            setElapsedTimePointer,
            to: (@convention(c) (Double) -> Void).self
        )
    }

    func play() {
        sendCommand(MediaRemoteAdapterCommand.play.rawValue, nil)
    }

    func pause() {
        sendCommand(MediaRemoteAdapterCommand.pause.rawValue, nil)
    }

    func togglePlayPause() {
        sendCommand(MediaRemoteAdapterCommand.togglePlayPause.rawValue, nil)
    }

    func nextTrack() {
        sendCommand(MediaRemoteAdapterCommand.nextTrack.rawValue, nil)
    }

    func previousTrack() {
        sendCommand(MediaRemoteAdapterCommand.previousTrack.rawValue, nil)
    }

    func seek(to time: Double) {
        setElapsedTime(max(0, time))
    }
}

private final class SystemMediaPlaybackPlayer: MediaPlaybackCommandPerforming {
    typealias ResourceProvider = () -> MediaRemoteAdapterResource?
    typealias ProcessLauncher = (_ executableURL: URL, _ arguments: [String]) -> Void

    private let commandController: (any MediaRemoteCommandControlling)?
    private let resourceProvider: ResourceProvider
    private let processLauncher: ProcessLauncher

    init(
        commandController: (any MediaRemoteCommandControlling)?,
        resourceProvider: @escaping ResourceProvider,
        processLauncher: @escaping ProcessLauncher
    ) {
        self.commandController = commandController
        self.resourceProvider = resourceProvider
        self.processLauncher = processLauncher
    }

    func perform(_ command: MediaPlaybackCommand) -> Bool {
        guard let resource = resourceProvider() else {
            return false
        }

        if let commandController {
            switch command {
            case .play:
                commandController.play()
            case .pause:
                commandController.pause()
            case .togglePlayPause:
                commandController.togglePlayPause()
            case .nextTrack:
                commandController.nextTrack()
            case .previousTrack:
                commandController.previousTrack()
            case let .seek(time):
                commandController.seek(to: time)
            }
            return true
        }

        switch command {
        case .play:
            send(.play, using: resource)
        case .pause:
            send(.pause, using: resource)
        case .togglePlayPause:
            send(.togglePlayPause, using: resource)
        case .nextTrack:
            send(.nextTrack, using: resource)
        case .previousTrack:
            send(.previousTrack, using: resource)
        case let .seek(time):
            let microseconds = max(0, Int(time * 1_000_000))
            processLauncher(
                URL(fileURLWithPath: "/usr/bin/perl"),
                [resource.scriptURL.path, resource.frameworkURL.path, "seek", "\(microseconds)"]
            )
        }

        return true
    }

    private func send(_ command: MediaRemoteAdapterCommand, using resource: MediaRemoteAdapterResource) {
        processLauncher(
            URL(fileURLWithPath: "/usr/bin/perl"),
            [resource.scriptURL.path, resource.frameworkURL.path, "send", "\(command.rawValue)"]
        )
    }
}

protocol MediaStreamProcessHandling: AnyObject, Sendable {
    var isRunning: Bool { get }
    var processIdentifier: pid_t { get }

    func terminate()
    func waitUntilExit()
}

final class MediaStreamProcessHandle: MediaStreamProcessHandling, @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var isRunning: Bool {
        process.isRunning
    }

    var processIdentifier: pid_t {
        process.processIdentifier
    }

    func terminate() {
        process.terminate()
    }

    func waitUntilExit() {
        process.waitUntilExit()
    }
}

struct MediaStreamProcessReaper: Sendable {
    typealias KillProcess = @Sendable (_ pid: pid_t, _ signal: Int32) -> Int32
    typealias Sleep = @Sendable (_ interval: TimeInterval) -> Void
    typealias Log = @Sendable (_ message: String) -> Void

    private let timeout: TimeInterval
    private let pollInterval: TimeInterval
    private let queue: DispatchQueue
    private let killProcess: KillProcess
    private let sleep: Sleep
    private let log: Log

    init(
        timeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.05,
        queue: DispatchQueue = DispatchQueue(label: "NotchPilot.MediaStreamProcessReaper", qos: .utility),
        killProcess: @escaping KillProcess = { Darwin.kill($0, $1) },
        sleep: @escaping Sleep = { Thread.sleep(forTimeInterval: $0) },
        log: @escaping Log = { NSLog("%@", $0) }
    ) {
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.queue = queue
        self.killProcess = killProcess
        self.sleep = sleep
        self.log = log
    }

    func reap(_ process: any MediaStreamProcessHandling) {
        if process.isRunning {
            process.terminate()
        }

        queue.async { [timeout, pollInterval, killProcess, sleep, log] in
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                sleep(pollInterval)
            }

            if process.isRunning {
                let pid = process.processIdentifier
                let result = killProcess(pid, SIGKILL)
                if result == 0 {
                    log("NotchPilot force killed unresponsive media stream process pid \(pid)")
                } else {
                    log("NotchPilot failed to force kill media stream process pid \(pid): errno \(errno)")
                }
            }

            process.waitUntilExit()
        }
    }
}

@MainActor
protocol NowPlayingSessionMonitoring: AnyObject {
    var currentState: MediaPlaybackState { get }
    var statePublisher: AnyPublisher<MediaPlaybackState, Never> { get }

    func start()
    func stop()
    func play()
    func pause()
    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(to time: Double)
    func currentPlaybackTime(for source: MediaPlaybackSource) async -> TimeInterval?
}

@MainActor
final class NowPlayingSessionMonitor: NowPlayingSessionMonitoring {
    private static let playbackTimeReconciliationInterval: TimeInterval = 1
    private static let playbackTimeReconciliationThreshold: TimeInterval = 1

    private(set) var currentState: MediaPlaybackState = .idle
    private let stateSubject = PassthroughSubject<MediaPlaybackState, Never>()
    var statePublisher: AnyPublisher<MediaPlaybackState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    private let commandController: (any MediaRemoteCommandControlling)? = SystemMediaRemoteCommandController()
    private let playbackTimeProvider: any PlaybackTimeProviding
    private let spotifyPlayer: any SpotifyPlaybackPlayerOperating
    private let streamProcessReaper: MediaStreamProcessReaper
    private let systemStateFetcher: (@MainActor () async -> MediaPlaybackState?)?
    private var streamProcess: (any MediaStreamProcessHandling)?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var playbackTimeReconciliationTask: Task<Void, Never>?
    private var playbackStateSelector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
    private var spotifyTrackGate = SpotifyPlaybackTrackGate()
    private var spotifyNotificationObserver: NSObjectProtocol?
    private var isMonitoring = false
    private var playbackTimeResolver = MediaPlaybackTimeResolver()
    private lazy var systemPlayer = SystemMediaPlaybackPlayer(
        commandController: commandController,
        resourceProvider: { [weak self] in
            self?.mediaRemoteAdapterResource
        },
        processLauncher: { [weak self] executableURL, arguments in
            self?.launchDetachedProcess(executableURL: executableURL, arguments: arguments)
        }
    )
    private lazy var commandRouter = MediaPlaybackPlayerCommandRouter(
        commandPerformers: [
            .spotify: spotifyPlayer,
            .system: systemPlayer,
        ],
        fallbackPlayer: .system
    )

    init(
        playbackTimeProvider: any PlaybackTimeProviding = AppleScriptPlaybackTimeProvider(),
        spotifyPlayer: any SpotifyPlaybackPlayerOperating = AppleScriptSpotifyPlaybackPlayer(),
        streamProcessReaper: MediaStreamProcessReaper = MediaStreamProcessReaper(),
        systemStateFetcher: (@MainActor () async -> MediaPlaybackState?)? = nil
    ) {
        self.playbackTimeProvider = playbackTimeProvider
        self.spotifyPlayer = spotifyPlayer
        self.streamProcessReaper = streamProcessReaper
        self.systemStateFetcher = systemStateFetcher
    }

    func start() {
        guard isMonitoring == false else {
            return
        }

        isMonitoring = true
        startSpotifyPlaybackObservation()
        startPlaybackTimeReconciliation()
        Task { [weak self] in
            await self?.refreshSpotifyPlaybackSnapshot()
        }

        guard let resource = mediaRemoteAdapterResource else {
            updateState(playbackStateSelector.update(.unavailable, for: .system))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [resource.scriptURL.path, resource.frameworkURL.path, "stream", "--no-diff"]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = pipeHandler.pipe
        process.standardError = Pipe()

        do {
            try process.run()
            self.streamProcess = MediaStreamProcessHandle(process)
            self.pipeHandler = pipeHandler
            self.streamTask = Task { [weak self] in
                await self?.consumeStream(with: pipeHandler)
            }
        } catch {
            updateState(playbackStateSelector.update(.unavailable, for: .system))
        }
    }

    func stop() {
        isMonitoring = false
        stopSpotifyPlaybackObservation()
        streamTask?.cancel()
        streamTask = nil
        playbackTimeReconciliationTask?.cancel()
        playbackTimeReconciliationTask = nil

        let pipeHandler = pipeHandler
        self.pipeHandler = nil
        Task {
            await pipeHandler?.close()
        }

        if let streamProcess {
            streamProcessReaper.reap(streamProcess)
        }
        self.streamProcess = nil
        spotifyTrackGate.reset()
        playbackStateSelector.reset()
        playbackTimeResolver.reset()
    }

    func play() {
        performCommand(
            .play,
            refreshDelays: [0.15, 0.6]
        )
    }

    func pause() {
        performCommand(
            .pause,
            refreshDelays: [0.15, 0.6]
        )
    }

    func playPause() {
        performCommand(
            .togglePlayPause,
            refreshDelays: [0.15, 0.6]
        )
    }

    func nextTrack() {
        performCommand(
            .nextTrack,
            refreshDelays: [0.2, 0.7]
        )
    }

    func previousTrack() {
        performCommand(
            .previousTrack,
            refreshDelays: [0.2, 0.7]
        )
    }

    func seek(to time: Double) {
        performCommand(
            .seek(time),
            refreshDelays: [0.15, 0.6]
        )
    }

    func currentPlaybackTime(for source: MediaPlaybackSource) async -> TimeInterval? {
        if Self.isSpotifySource(source) {
            return await spotifyPlayer.currentPlaybackTime()
        }

        return await playbackTimeProvider.currentPlaybackTime(for: source)
    }

    func reconcilePlaybackTime(at date: Date = Date(), requiresMonitoring: Bool = false) async {
        guard requiresMonitoring == false || isMonitoring,
              case let .active(snapshot) = currentState,
              snapshot.isPlaying
        else {
            return
        }

        guard let playbackTime = await currentPlaybackTime(for: snapshot.source) else {
            guard requiresMonitoring == false || isMonitoring else {
                return
            }

            if playerID(for: snapshot.source) == .system {
                await refreshCurrentSystemState(at: date)
            }
            return
        }

        guard requiresMonitoring == false || isMonitoring else {
            return
        }

        let estimatedTime = snapshot.estimatedCurrentTime(at: date)
        guard abs(playbackTime - estimatedTime) >= Self.playbackTimeReconciliationThreshold else {
            return
        }

        let state = MediaPlaybackState.active(snapshot.replacingCurrentTime(playbackTime, at: date))
        updateState(playbackStateSelector.update(state, for: playerID(for: snapshot.source), at: date))
    }

    func updateState(_ state: MediaPlaybackState) {
        let resolvedState = playbackTimeResolver.resolve(state)
        currentState = resolvedState
        stateSubject.send(resolvedState)
    }

    private func consumeStream(with pipeHandler: JSONLinesPipeHandler) async {
        await pipeHandler.readJSONLines(as: AdapterUpdate.self) { [weak self] update in
            await MainActor.run {
                self?.handleAdapterUpdate(update)
            }
        }
    }

    private func handleAdapterUpdate(_ update: AdapterUpdate) {
        let state = playbackStateSelector.update(update.normalizedState, for: .system)
        updateState(state)
    }

    private func startPlaybackTimeReconciliation() {
        guard playbackTimeReconciliationTask == nil else {
            return
        }

        playbackTimeReconciliationTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(Self.playbackTimeReconciliationInterval))
                guard Task.isCancelled == false else {
                    return
                }

                await self?.reconcilePlaybackTime(requiresMonitoring: true)
            }
        }
    }

    private func startSpotifyPlaybackObservation() {
        guard spotifyNotificationObserver == nil else {
            return
        }

        spotifyNotificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: SpotifyPlaybackNotice.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let payload = SpotifyPlaybackNotice.payload(from: userInfo) else {
                return
            }

            Task { @MainActor [weak self, payload] in
                await self?.handleSpotifyPlaybackPayload(payload)
            }
        }
    }

    private func stopSpotifyPlaybackObservation() {
        if let spotifyNotificationObserver {
            DistributedNotificationCenter.default().removeObserver(spotifyNotificationObserver)
            self.spotifyNotificationObserver = nil
        }
    }

    @discardableResult
    private func refreshSpotifyPlaybackSnapshot() async -> Bool {
        let date = Date()
        guard let snapshot = await spotifyPlayer.currentSpotifyPlaybackSnapshot(at: date) else {
            return false
        }

        let state = MediaPlaybackState.active(snapshot)
        updateState(playbackStateSelector.update(state, for: .spotify, at: date))
        return true
    }

    private func handleSpotifyPlaybackPayload(_ payload: SpotifyPlaybackNotice.Payload) async {
        guard isMonitoring else {
            return
        }

        await applySpotifyPlaybackPayload(payload)
    }

    func applySpotifyPlaybackPayload(_ payload: SpotifyPlaybackNotice.Payload) async {
        let date = Date()
        if payload.playback == .playing,
           spotifyTrackGate.shouldRefreshCompleteSnapshot(for: payload.trackID),
           await refreshSpotifyPlaybackSnapshot() {
            spotifyTrackGate.accept(payload.trackID)
            return
        }

        guard let state = await SpotifyPlaybackNotice.state(
                from: payload,
                fallback: playbackStateSelector.snapshot(for: .spotify, at: date),
                at: date
        ) else {
            return
        }

        switch payload.playback {
        case .playing:
            spotifyTrackGate.accept(payload.trackID)
        case .paused:
            break
        case .stopped:
            spotifyTrackGate.reset()
        }
        updateState(playbackStateSelector.update(state, for: .spotify, at: date))
    }

    private func requestStateRefresh(using resource: MediaRemoteAdapterResource, after delay: TimeInterval) {
        Task.detached(priority: .utility) { [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard let state = await Self.fetchCurrentState(using: resource) else {
                return
            }

            await self?.applyRefreshedState(state)
        }
    }

    private func performCommand(
        _ command: MediaPlaybackCommand,
        refreshDelays: [TimeInterval]
    ) {
        guard let player = commandRouter.perform(command, selectedPlayer: playbackStateSelector.currentPlayer) else {
            return
        }

        for delay in refreshDelays {
            requestStateRefresh(for: player, after: delay)
        }
    }

    private func requestStateRefresh(for player: MediaPlaybackPlayerID, after delay: TimeInterval) {
        switch player {
        case .spotify:
            requestSpotifyPlaybackSnapshot(after: delay)
        case .system:
            guard let resource = mediaRemoteAdapterResource else {
                return
            }
            requestStateRefresh(using: resource, after: delay)
        }
    }

    @discardableResult
    private func refreshCurrentSystemState(at date: Date = Date()) async -> Bool {
        guard let state = await currentSystemState() else {
            return false
        }

        updateState(playbackStateSelector.update(state, for: .system, at: date))
        return true
    }

    private func currentSystemState() async -> MediaPlaybackState? {
        if let systemStateFetcher {
            return await systemStateFetcher()
        }

        guard let resource = mediaRemoteAdapterResource else {
            return nil
        }

        return await Self.fetchCurrentState(using: resource)
    }

    private func requestSpotifyPlaybackSnapshot(after delay: TimeInterval) {
        Task.detached(priority: .utility) { [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await self?.refreshSpotifyPlaybackSnapshot()
        }
    }

    private var mediaRemoteAdapterResource: MediaRemoteAdapterResource? {
        guard let resourceURL = Bundle.module.resourceURL else {
            return nil
        }

        let adapterDirectoryURL = resourceURL.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
        let scriptURL = adapterDirectoryURL.appendingPathComponent("mediaremote-adapter.pl")
        let frameworkURL = adapterDirectoryURL.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)

        guard
            FileManager.default.fileExists(atPath: scriptURL.path),
            FileManager.default.fileExists(atPath: frameworkURL.path)
        else {
            return nil
        }

        return MediaRemoteAdapterResource(scriptURL: scriptURL, frameworkURL: frameworkURL)
    }

    private static func isSpotifySource(_ source: MediaPlaybackSource) -> Bool {
        source.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("spotify") == true ||
            source.displayName.lowercased().contains("spotify")
    }

    private func playerID(for source: MediaPlaybackSource) -> MediaPlaybackPlayerID {
        Self.isSpotifySource(source) ? .spotify : .system
    }

    private func launchDetachedProcess(executableURL: URL, arguments: [String]) {
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }
        }
    }

    @MainActor
    private func applyRefreshedState(_ state: MediaPlaybackState) {
        updateState(playbackStateSelector.update(state, for: .system))
    }

    private static func fetchCurrentState(using resource: MediaRemoteAdapterResource) async -> MediaPlaybackState? {
        await Task.detached(priority: .utility) {
            guard let output = ProcessOutputCapture.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                arguments: [resource.scriptURL.path, resource.frameworkURL.path, "get"],
                timeout: 2
            ), output.terminationStatus == 0, output.standardOutput.isEmpty == false else {
                return nil
            }

            return MediaRemoteAdapterCurrentStateDecoder.state(from: output.standardOutput)
        }.value
    }
}

private struct MediaRemoteAdapterResource {
    let scriptURL: URL
    let frameworkURL: URL
}

private struct AdapterUpdate: Decodable, Sendable {
    let normalizedState: MediaPlaybackState

    private enum CodingKeys: String, CodingKey {
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeNil(forKey: .payload) {
            normalizedState = .idle
        } else {
            normalizedState = try container.decode(AdapterPayload.self, forKey: .payload).normalizedState
        }
    }
}

private struct AdapterPayload: Decodable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?

    var normalizedState: MediaPlaybackState {
        NowPlayingSessionPayload(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsedTime,
            artworkData: artworkData.flatMap {
                Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            timestamp: timestamp.flatMap(AdapterTimestampParser.date(from:)),
            playbackRate: playbackRate,
            isPlaying: playing,
            parentApplicationBundleIdentifier: parentApplicationBundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            volume: volume
        ).normalizedState
    }
}

enum MediaRemoteAdapterCurrentStateDecoder {
    static func state(from data: Data) -> MediaPlaybackState? {
        let trimmedOutput = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmedOutput, trimmedOutput.isEmpty == false else {
            return nil
        }

        guard trimmedOutput != "null" else {
            return .idle
        }

        return try? JSONDecoder().decode(AdapterPayload.self, from: data).normalizedState
    }
}

private enum AdapterTimestampParser {
    nonisolated(unsafe) private static let formatter = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func date(from timestamp: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: timestamp)
    }
}

actor JSONLinesPipeHandler {
    nonisolated let pipe = Pipe()
    private let fileHandle: FileHandle
    private var buffer = Data()
    private var pendingRead: CheckedContinuation<Data, Error>?
    private var isClosed = false

    init() {
        self.fileHandle = pipe.fileHandleForReading
    }

    func readJSONLines<T: Decodable & Sendable>(
        as type: T.Type,
        onLine: @escaping @Sendable (T) async -> Void
    ) async {
        do {
            try await processLines(as: type, onLine: onLine)
        } catch {
            return
        }
    }

    func close() async {
        isClosed = true
        fileHandle.readabilityHandler = nil
        pendingRead?.resume(returning: Data())
        pendingRead = nil
        try? fileHandle.close()
    }

    private func processLines<T: Decodable & Sendable>(
        as type: T.Type,
        onLine: @escaping @Sendable (T) async -> Void
    ) async throws {
        while true {
            let data = try await readData()
            guard data.isEmpty == false else {
                break
            }

            buffer.append(data)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                var lineData = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)

                if lineData.last == 0x0D {
                    lineData.removeLast()
                }

                guard lineData.isEmpty == false else {
                    continue
                }

                if let decodedObject = try? JSONDecoder().decode(T.self, from: lineData) {
                    await onLine(decodedObject)
                }
            }
        }
    }

    private func readData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            guard isClosed == false else {
                continuation.resume(returning: Data())
                return
            }

            pendingRead = continuation
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                Task {
                    await self.completeRead(with: data)
                }
            }
        }
    }

    private func completeRead(with data: Data) {
        fileHandle.readabilityHandler = nil
        pendingRead?.resume(returning: data)
        pendingRead = nil
    }
}
