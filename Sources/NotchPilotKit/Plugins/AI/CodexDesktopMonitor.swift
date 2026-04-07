import Foundation

public enum CodexDesktopConnectionStatus: String, Equatable, Sendable {
    case notFound
    case disconnected
    case connecting
    case connected
    case error
}

public struct CodexDesktopConnectionState: Equatable, Sendable {
    public let status: CodexDesktopConnectionStatus
    public let message: String?

    public init(status: CodexDesktopConnectionStatus, message: String? = nil) {
        self.status = status
        self.message = message
    }

    public static let notFound = CodexDesktopConnectionState(status: .notFound)
    public static let disconnected = CodexDesktopConnectionState(status: .disconnected)
    public static let connecting = CodexDesktopConnectionState(status: .connecting)
    public static let connected = CodexDesktopConnectionState(status: .connected)
}

public final class CodexDesktopMonitor: @unchecked Sendable, CodexDesktopContextMonitoring {
    public var onThreadContextChanged: (@Sendable (CodexThreadContext) -> Void)?
    public var onConnectionStateChanged: (@Sendable (CodexDesktopConnectionState) -> Void)?

    private let queue = DispatchQueue(label: "NotchPilot.CodexDesktopMonitor")
    private let detector: CodexDesktopAppDetector
    private let discovery: CodexDesktopIPCDiscovery
    private let requestTimeout: TimeInterval

    private var client: CodexDesktopIPCClient?
    private var reducer = CodexDesktopEventReducer()
    private var isRunning = false
    private var retryWorkItem: DispatchWorkItem?

    public init(
        detector: CodexDesktopAppDetector = CodexDesktopAppDetector(),
        discovery: CodexDesktopIPCDiscovery = CodexDesktopIPCDiscovery(),
        requestTimeout: TimeInterval = 20
    ) {
        self.detector = detector
        self.discovery = discovery
        self.requestTimeout = requestTimeout
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.isRunning == false else {
                return
            }
            self.isRunning = true
            self.attemptConnect()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.retryWorkItem?.cancel()
            self.retryWorkItem = nil
            try? self.client?.disconnect()
            self.client = nil
        }
    }

    private func attemptConnect() {
        guard isRunning else {
            return
        }

        retryWorkItem?.cancel()
        retryWorkItem = nil

        guard detector.isInstalled() else {
            emitConnectionState(.notFound)
            scheduleRetry()
            return
        }

        let socketPaths = (try? discovery.discoverSocketPaths()) ?? []
        guard socketPaths.isEmpty == false else {
            emitConnectionState(.disconnected)
            scheduleRetry()
            return
        }

        emitConnectionState(.connecting)

        var lastError: String?
        for socketPath in socketPaths {
            let client = CodexDesktopIPCClient(socketPath: socketPath, requestTimeout: requestTimeout)
            client.onFrame = { [weak self] frame in
                guard let self else { return }
                self.queue.async { [self] in
                    self.handle(frame: frame)
                }
            }
            client.onDisconnect = { [weak self] reason in
                guard let self else { return }
                self.queue.async { [self] in
                    self.handleDisconnect(reason: reason)
                }
            }

            do {
                try client.connect()
                _ = try client.initialize()
                self.client = client
                emitConnectionState(.connected)
                return
            } catch {
                lastError = error.localizedDescription
                try? client.disconnect()
            }
        }

        emitConnectionState(CodexDesktopConnectionState(status: .error, message: lastError))
        scheduleRetry()
    }

    private func handle(frame: CodexDesktopIPCFrame) {
        guard let client else {
            return
        }

        switch frame {
        case let .clientDiscoveryRequest(requestID, request):
            try? client.sendClientDiscoveryResponse(
                requestID: requestID,
                canHandle: Self.canHandleDiscoveryRequest(request)
            )
        case let .request(request):
            try? client.sendErrorResponse(requestID: request.requestID, message: "no-handler-for-request")
        case .broadcast:
            emitOutputs((try? reducer.consume(frame: frame)) ?? [])
        case .response, .clientDiscoveryResponse:
            break
        }
    }

    private func emitOutputs(_ outputs: [CodexDesktopReducerOutput]) {
        for output in outputs {
            switch output {
            case let .threadContextUpsert(context):
                onThreadContextChanged?(context)
            }
        }
    }

    private func handleDisconnect(reason: String?) {
        client = nil
        emitConnectionState(
            reason == nil
                ? .disconnected
                : CodexDesktopConnectionState(status: .error, message: reason)
        )
        scheduleRetry()
    }

    private func emitConnectionState(_ state: CodexDesktopConnectionState) {
        onConnectionStateChanged?(state)
    }

    private func scheduleRetry(after delay: TimeInterval = 3) {
        guard isRunning else {
            return
        }

        retryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptConnect()
        }
        retryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    static func canHandleDiscoveryRequest(_: CodexDesktopIPCRequestFrame?) -> Bool {
        return false
    }
}
