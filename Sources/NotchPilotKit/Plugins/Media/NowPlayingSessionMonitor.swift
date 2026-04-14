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
}

@MainActor
final class NowPlayingSessionMonitor: NowPlayingSessionMonitoring {
    private(set) var currentState: MediaPlaybackState = .idle
    var onStateChange: (@MainActor (MediaPlaybackState) -> Void)?

    private let commandController: (any MediaRemoteCommandControlling)? = SystemMediaRemoteCommandController()
    private var streamProcess: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    func start() {
        guard streamProcess == nil else {
            return
        }

        guard let resource = mediaRemoteAdapterResource else {
            updateState(.unavailable)
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
            self.streamProcess = process
            self.pipeHandler = pipeHandler
            self.streamTask = Task { [weak self] in
                await self?.consumeStream(with: pipeHandler)
            }
        } catch {
            updateState(.unavailable)
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil

        Task {
            await pipeHandler?.close()
        }
        pipeHandler = nil

        if let streamProcess, streamProcess.isRunning {
            streamProcess.terminate()
            streamProcess.waitUntilExit()
        }
        self.streamProcess = nil
    }

    func play() {
        performCommand(
            directCommand: { $0.play() },
            fallbackCommand: .play,
            refreshDelays: [0.15, 0.6]
        )
    }

    func pause() {
        performCommand(
            directCommand: { $0.pause() },
            fallbackCommand: .pause,
            refreshDelays: [0.15, 0.6]
        )
    }

    func playPause() {
        performCommand(
            directCommand: { $0.togglePlayPause() },
            fallbackCommand: .togglePlayPause,
            refreshDelays: [0.15, 0.6]
        )
    }

    func nextTrack() {
        performCommand(
            directCommand: { $0.nextTrack() },
            fallbackCommand: .nextTrack,
            refreshDelays: [0.2, 0.7]
        )
    }

    func previousTrack() {
        performCommand(
            directCommand: { $0.previousTrack() },
            fallbackCommand: .previousTrack,
            refreshDelays: [0.2, 0.7]
        )
    }

    func seek(to time: Double) {
        guard let resource = mediaRemoteAdapterResource else {
            return
        }

        if let commandController {
            commandController.seek(to: time)
        } else {
            let microseconds = max(0, Int(time * 1_000_000))
            launchDetachedProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                arguments: [resource.scriptURL.path, resource.frameworkURL.path, "seek", "\(microseconds)"]
            )
        }
        requestStateRefresh(using: resource, after: 0.15)
        requestStateRefresh(using: resource, after: 0.6)
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
        updateState(update.payload.normalizedState)
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

    private func send(command: MediaRemoteAdapterCommand) {
        guard let resource = mediaRemoteAdapterResource else {
            return
        }

        launchDetachedProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: [resource.scriptURL.path, resource.frameworkURL.path, "send", "\(command.rawValue)"]
        )
    }

    private func performCommand(
        directCommand: ((any MediaRemoteCommandControlling) -> Void)?,
        fallbackCommand: MediaRemoteAdapterCommand,
        refreshDelays: [TimeInterval]
    ) {
        guard let resource = mediaRemoteAdapterResource else {
            return
        }

        if let commandController, let directCommand {
            directCommand(commandController)
        } else {
            send(command: fallbackCommand)
        }

        for delay in refreshDelays {
            requestStateRefresh(using: resource, after: delay)
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
        updateState(state)
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
