import Darwin
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
    var onStateChange: (@MainActor (MediaPlaybackState) -> Void)? { get set }

    func start()
    func stop()
    func play()
    func pause()
    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(to time: Double)
    func currentPlaybackTime(for source: MediaPlaybackSource) -> TimeInterval?
}

@MainActor
final class NowPlayingSessionMonitor: NowPlayingSessionMonitoring {
    private(set) var currentState: MediaPlaybackState = .idle
    var onStateChange: (@MainActor (MediaPlaybackState) -> Void)?

    private let commandController: (any MediaRemoteCommandControlling)? = SystemMediaRemoteCommandController()
    private let playbackTimeProvider: any PlaybackTimeProviding
    private let spotifyPlayer: any SpotifyPlaybackPlayerOperating
    private let streamProcessReaper: MediaStreamProcessReaper
    private var streamProcess: (any MediaStreamProcessHandling)?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var playbackStateSelector = MediaPlaybackPlayerSelector(players: [.spotify, .system])
    private var spotifyTrackGate = SpotifyPlaybackTrackGate()
    private var spotifyNotificationObserver: NSObjectProtocol?
    private var isMonitoring = false
    private lazy var systemPlayer = SystemMediaPlaybackPlayer(
        commandController: commandController,
        resourceProvider: { [weak self] in
            self?.mediaRemoteAdapterResource
        },
        processLauncher: { [weak self] executableURL, arguments in
            self?.launchDetachedProcess(executableURL: executableURL, arguments: arguments)
        }
    )

    init(
        playbackTimeProvider: any PlaybackTimeProviding = AppleScriptPlaybackTimeProvider(),
        spotifyPlayer: any SpotifyPlaybackPlayerOperating = AppleScriptSpotifyPlaybackPlayer(),
        streamProcessReaper: MediaStreamProcessReaper = MediaStreamProcessReaper()
    ) {
        self.playbackTimeProvider = playbackTimeProvider
        self.spotifyPlayer = spotifyPlayer
        self.streamProcessReaper = streamProcessReaper
    }

    func start() {
        guard isMonitoring == false else {
            return
        }

        isMonitoring = true
        startSpotifyPlaybackObservation()
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

    func currentPlaybackTime(for source: MediaPlaybackSource) -> TimeInterval? {
        if Self.isSpotifySource(source) {
            return spotifyPlayer.currentPlaybackTime()
        }

        return playbackTimeProvider.currentPlaybackTime(for: source)
    }

    func updateState(_ state: MediaPlaybackState) {
        currentState = state
        onStateChange?(state)
    }

    private func consumeStream(with pipeHandler: JSONLinesPipeHandler) async {
        await pipeHandler.readJSONLines(as: AdapterUpdate.self) { [weak self] update in
            await MainActor.run {
                self?.handleAdapterUpdate(update)
            }
        }
    }

    private func handleAdapterUpdate(_ update: AdapterUpdate) {
        let state = playbackStateSelector.update(update.payload.normalizedState, for: .system)
        updateState(state)
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
        if spotifyTrackGate.shouldRefreshCompleteSnapshot(for: payload.trackID),
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

        spotifyTrackGate.accept(payload.trackID)
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
        let router = MediaPlaybackPlayerCommandRouter(
            commandPerformers: [
                .spotify: spotifyPlayer,
                .system: systemPlayer,
            ],
            fallbackPlayer: .system
        )

        guard let player = router.perform(command, selectedPlayer: playbackStateSelector.currentPlayer) else {
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
            let outputPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [resource.scriptURL.path, resource.frameworkURL.path, "get"]
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    return nil
                }

                let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
                guard outputData.isEmpty == false else {
                    return nil
                }

                return try? JSONDecoder().decode(AdapterPayload.self, from: outputData).normalizedState
            } catch {
                return nil
            }
        }.value
    }
}

private struct MediaRemoteAdapterResource {
    let scriptURL: URL
    let frameworkURL: URL
}

private struct AdapterUpdate: Decodable, Sendable {
    let payload: AdapterPayload
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
            timestamp: timestamp.flatMap(ISO8601DateFormatter().date(from:)),
            playbackRate: playbackRate,
            isPlaying: playing,
            parentApplicationBundleIdentifier: parentApplicationBundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            volume: volume
        ).normalizedState
    }
}

private actor JSONLinesPipeHandler {
    let pipe = Pipe()
    private let fileHandle: FileHandle
    private var buffer = ""

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
        fileHandle.readabilityHandler = nil
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

            guard let chunk = String(data: data, encoding: .utf8) else {
                continue
            }

            buffer.append(chunk)

            while let range = buffer.range(of: "\n") {
                let line = String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])

                guard line.isEmpty == false, let jsonData = line.data(using: .utf8) else {
                    continue
                }

                if let decodedObject = try? JSONDecoder().decode(T.self, from: jsonData) {
                    await onLine(decodedObject)
                }
            }
        }
    }

    private func readData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
}
