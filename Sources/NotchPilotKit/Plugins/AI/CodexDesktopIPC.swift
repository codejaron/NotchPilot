import Darwin
import Foundation

public enum CodexDesktopIPCError: LocalizedError, Equatable {
    case invalidFrame
    case unsupportedFrameType(String)
    case oversizedFrame(Int)
    case socketCreationFailed
    case invalidSocketPath
    case connectFailed(code: Int32)
    case disconnected
    case requestTimedOut(String)
    case responseError(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidFrame:
            return "Invalid Codex Desktop IPC frame."
        case let .unsupportedFrameType(type):
            return "Unsupported Codex Desktop IPC frame type: \(type)"
        case let .oversizedFrame(size):
            return "Codex Desktop IPC frame exceeded the size limit: \(size)"
        case .socketCreationFailed:
            return "Unable to create Codex Desktop IPC socket."
        case .invalidSocketPath:
            return "Invalid Codex Desktop IPC socket path."
        case let .connectFailed(code):
            return "Failed to connect to Codex Desktop IPC socket (\(code))."
        case .disconnected:
            return "Codex Desktop IPC disconnected."
        case let .requestTimedOut(method):
            return "Codex Desktop IPC request timed out: \(method)"
        case let .responseError(message):
            return "Codex Desktop IPC request failed: \(message)"
        case .invalidResponse:
            return "Invalid Codex Desktop IPC response."
        }
    }
}

public struct CodexDesktopIPCRequestFrame: Equatable, Sendable {
    public let requestID: String
    public let method: String
    public let params: [String: JSONValue]
    public let sourceClientID: String
    public let targetClientID: String?
    public let version: Int?

    public init(
        requestID: String,
        method: String,
        params: [String: JSONValue],
        sourceClientID: String,
        targetClientID: String?,
        version: Int?
    ) {
        self.requestID = requestID
        self.method = method
        self.params = params
        self.sourceClientID = sourceClientID
        self.targetClientID = targetClientID
        self.version = version
    }
}

public struct CodexDesktopIPCBroadcastFrame: Equatable, Sendable {
    public let method: String
    public let params: [String: JSONValue]
    public let sourceClientID: String
    public let targetClientID: String?
    public let version: Int?

    public init(
        method: String,
        params: [String: JSONValue],
        sourceClientID: String,
        targetClientID: String?,
        version: Int?
    ) {
        self.method = method
        self.params = params
        self.sourceClientID = sourceClientID
        self.targetClientID = targetClientID
        self.version = version
    }
}

public struct CodexDesktopIPCResponseFrame: Equatable, Sendable {
    public let requestID: String
    public let method: String?
    public let result: JSONValue?
    public let error: JSONValue?

    public init(requestID: String, method: String? = nil, result: JSONValue?, error: JSONValue?) {
        self.requestID = requestID
        self.method = method
        self.result = result
        self.error = error
    }
}

public enum CodexDesktopIPCFrame: Equatable, Sendable {
    case request(CodexDesktopIPCRequestFrame)
    case response(CodexDesktopIPCResponseFrame)
    case broadcast(CodexDesktopIPCBroadcastFrame)
    case clientDiscoveryRequest(requestID: String, request: CodexDesktopIPCRequestFrame?)
    case clientDiscoveryResponse(requestID: String, canHandle: Bool)
}

public enum CodexDesktopIPCCodec {
    public static let maxFrameSizeBytes = 256 * 1024 * 1024

    public static func encode(frame: CodexDesktopIPCFrame) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: frame.jsonObject, options: [])
        var data = Data(count: 4)
        data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            baseAddress.assumingMemoryBound(to: UInt32.self).pointee = UInt32(payload.count).littleEndian
        }
        data.append(payload)
        return data
    }

    public static func decodeFrames(from buffer: inout Data) throws -> [CodexDesktopIPCFrame] {
        var frames: [CodexDesktopIPCFrame] = []

        while buffer.count >= 4 {
            let frameSize = buffer.prefix(4).withUnsafeBytes { rawBuffer in
                rawBuffer.load(as: UInt32.self).littleEndian
            }

            if Int(frameSize) > maxFrameSizeBytes {
                throw CodexDesktopIPCError.oversizedFrame(Int(frameSize))
            }

            if buffer.count < 4 + Int(frameSize) {
                break
            }

            let payload = buffer.subdata(in: 4 ..< 4 + Int(frameSize))
            buffer.removeSubrange(0 ..< 4 + Int(frameSize))

            let rawObject = try JSONSerialization.jsonObject(with: payload, options: [])
            guard let dictionary = rawObject as? [String: Any] else {
                throw CodexDesktopIPCError.invalidFrame
            }

            frames.append(try decodeFrame(dictionary))
        }

        return frames
    }

    private static func decodeFrame(_ dictionary: [String: Any]) throws -> CodexDesktopIPCFrame {
        guard let type = dictionary["type"] as? String else {
            throw CodexDesktopIPCError.invalidFrame
        }

        switch type {
        case "request":
            return .request(try decodeRequestFrame(dictionary))
        case "broadcast":
            guard
                let method = dictionary["method"] as? String,
                let sourceClientID = dictionary["sourceClientId"] as? String
            else {
                throw CodexDesktopIPCError.invalidFrame
            }

            let params = try (dictionary["params"] as? [String: Any] ?? [:]).mapValues(JSONValue.init(jsonObject:))
            return .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: method,
                    params: params,
                    sourceClientID: sourceClientID,
                    targetClientID: dictionary["targetClientId"] as? String,
                    version: dictionary["version"] as? Int
                )
            )
        case "response":
            guard let requestID = dictionary["requestId"] as? String else {
                throw CodexDesktopIPCError.invalidFrame
            }

            let resultType = dictionary["resultType"] as? String ?? "success"
            let result = dictionary["result"].map { try? JSONValue(jsonObject: $0) } ?? nil
            let error = dictionary["error"].map { try? JSONValue(jsonObject: $0) } ?? nil

            return .response(
                CodexDesktopIPCResponseFrame(
                    requestID: requestID,
                    method: dictionary["method"] as? String,
                    result: resultType == "error" ? nil : result,
                    error: resultType == "error" ? error : nil
                )
            )
        case "client-discovery-request":
            guard let requestID = dictionary["requestId"] as? String else {
                throw CodexDesktopIPCError.invalidFrame
            }
            let nestedRequest = try (dictionary["request"] as? [String: Any]).map(decodeRequestFrame(_:))
            return .clientDiscoveryRequest(requestID: requestID, request: nestedRequest)
        case "client-discovery-response":
            guard
                let requestID = dictionary["requestId"] as? String,
                let response = dictionary["response"] as? [String: Any]
            else {
                throw CodexDesktopIPCError.invalidFrame
            }
            return .clientDiscoveryResponse(
                requestID: requestID,
                canHandle: response["canHandle"] as? Bool ?? false
            )
        default:
            throw CodexDesktopIPCError.unsupportedFrameType(type)
        }
    }

    private static func decodeRequestFrame(_ dictionary: [String: Any]) throws -> CodexDesktopIPCRequestFrame {
        guard
            let requestID = dictionary["requestId"] as? String,
            let method = dictionary["method"] as? String,
            let sourceClientID = dictionary["sourceClientId"] as? String
        else {
            throw CodexDesktopIPCError.invalidFrame
        }

        let params = try (dictionary["params"] as? [String: Any] ?? [:]).mapValues(JSONValue.init(jsonObject:))
        return CodexDesktopIPCRequestFrame(
            requestID: requestID,
            method: method,
            params: params,
            sourceClientID: sourceClientID,
            targetClientID: dictionary["targetClientId"] as? String,
            version: dictionary["version"] as? Int
        )
    }
}

private extension CodexDesktopIPCFrame {
    var jsonObject: [String: Any] {
        switch self {
        case let .request(frame):
            var object: [String: Any] = [
                "type": "request",
                "requestId": frame.requestID,
                "method": frame.method,
                "params": frame.params.mapValues(\.jsonObject),
                "sourceClientId": frame.sourceClientID,
            ]
            if let targetClientID = frame.targetClientID {
                object["targetClientId"] = targetClientID
            }
            if let version = frame.version {
                object["version"] = version
            }
            return object
        case let .broadcast(frame):
            var object: [String: Any] = [
                "type": "broadcast",
                "method": frame.method,
                "params": frame.params.mapValues(\.jsonObject),
                "sourceClientId": frame.sourceClientID,
            ]
            if let targetClientID = frame.targetClientID {
                object["targetClientId"] = targetClientID
            }
            if let version = frame.version {
                object["version"] = version
            }
            return object
        case let .response(frame):
            var object: [String: Any] = [
                "type": "response",
                "requestId": frame.requestID,
            ]
            if let method = frame.method {
                object["method"] = method
            }
            if let error = frame.error {
                object["resultType"] = "error"
                object["error"] = error.jsonObject
            } else {
                object["resultType"] = "success"
                if let result = frame.result {
                    object["result"] = result.jsonObject
                }
            }
            return object
        case let .clientDiscoveryRequest(requestID, request):
            var object: [String: Any] = [
                "type": "client-discovery-request",
                "requestId": requestID,
            ]
            if let request {
                object["request"] = CodexDesktopIPCFrame.request(request).jsonObject
            }
            return object
        case let .clientDiscoveryResponse(requestID, canHandle):
            return [
                "type": "client-discovery-response",
                "requestId": requestID,
                "response": [
                    "canHandle": canHandle,
                ],
            ]
        }
    }
}

public struct CodexDesktopIPCDiscovery {
    public let directoryURLs: [URL]
    private let fileManager: FileManager

    public init(
        directoryURLs: [URL] = [
            FileManager.default.temporaryDirectory.appendingPathComponent("codex-ipc", isDirectory: true),
            URL(fileURLWithPath: "/tmp/codex-ipc", isDirectory: true),
        ],
        fileManager: FileManager = .default
    ) {
        self.directoryURLs = Array(
            Set(directoryURLs.map { $0.standardizedFileURL.path })
        )
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.fileManager = fileManager
    }

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.init(directoryURLs: [directoryURL], fileManager: fileManager)
    }

    public func discoverSocketPaths() throws -> [String] {
        var urls: [URL] = []

        for directoryURL in directoryURLs where fileManager.fileExists(atPath: directoryURL.path) {
            let directoryEntries = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            urls.append(contentsOf: directoryEntries)
        }

        return try urls
            .filter { $0.lastPathComponent.hasPrefix("ipc-") && $0.pathExtension == "sock" }
            .sorted {
                let lhsDate = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let rhsDate = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
            .map(\.path)
    }
}

public struct CodexDesktopAppDetector {
    private let fileManager: FileManager
    private let homeDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
    }

    public func isInstalled() -> Bool {
        let candidatePaths = [
            "/Applications/Codex.app",
            homeDirectoryURL.appendingPathComponent("Applications/Codex.app", isDirectory: true).path,
            homeDirectoryURL.appendingPathComponent(".codex", isDirectory: true).path,
        ]

        return candidatePaths.contains { fileManager.fileExists(atPath: $0) }
    }
}

public final class CodexDesktopIPCClient {
    public var onFrame: (@Sendable (CodexDesktopIPCFrame) -> Void)?
    public var onDisconnect: (@Sendable (String?) -> Void)?

    private let socketPath: String
    private let requestTimeout: TimeInterval
    private let readQueue = DispatchQueue(label: "NotchPilot.CodexDesktopIPCClient.read")
    private let lock = NSLock()

    private var socketFileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    private var clientID: String?
    private var pendingRequests: [String: PendingRequest] = [:]

    public init(socketPath: String, requestTimeout: TimeInterval = 20) {
        self.socketPath = socketPath
        self.requestTimeout = requestTimeout
    }

    deinit {
        try? disconnect()
    }

    public func connect() throws {
        guard socketFileDescriptor < 0 else {
            return
        }

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw CodexDesktopIPCError.socketCreationFailed
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxLength else {
            close(fileDescriptor)
            throw CodexDesktopIPCError.invalidSocketPath
        }

        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { pathCString in
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    pathCString,
                    maxLength - 1
                )
            }
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                Darwin.connect(fileDescriptor, addressPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            let errorCode = errno
            close(fileDescriptor)
            throw CodexDesktopIPCError.connectFailed(code: errorCode)
        }

        socketFileDescriptor = fileDescriptor

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: readQueue)
        readSource.setEventHandler { [weak self] in
            self?.readAvailableData()
        }
        readSource.resume()
        self.readSource = readSource
    }

    public func disconnect() throws {
        guard socketFileDescriptor >= 0 else {
            return
        }

        let fileDescriptor = socketFileDescriptor
        socketFileDescriptor = -1
        clientID = nil
        readSource?.cancel()
        readSource = nil
        rejectPendingRequests(with: CodexDesktopIPCError.disconnected)
        shutdown(fileDescriptor, SHUT_RDWR)
        close(fileDescriptor)
    }

    public func initialize(clientType: String = "notchpilot") throws -> String {
        let response = try sendRequestAndWait(
            method: "initialize",
            params: [
                "clientType": .string(clientType),
            ],
            sourceClientID: "initializing-client",
            version: 1
        )

        guard let clientID = response.result?.objectValue?["clientId"]?.stringValue else {
            throw CodexDesktopIPCError.invalidResponse
        }

        self.clientID = clientID
        return clientID
    }

    public func sendClientDiscoveryResponse(requestID: String, canHandle: Bool) throws {
        try write(frame: .clientDiscoveryResponse(requestID: requestID, canHandle: canHandle))
    }

    public func sendErrorResponse(requestID: String, message: String) throws {
        try write(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: requestID,
                    result: nil,
                    error: .string(message)
                )
            )
        )
    }

    public func sendSuccessResponse(requestID: String, method: String? = nil, result: JSONValue) throws {
        try write(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: requestID,
                    method: method,
                    result: result,
                    error: nil
                )
            )
        )
    }

    public func sendRequestAndWait(
        method: String,
        params: [String: JSONValue],
        sourceClientID: String? = nil,
        targetClientID: String? = nil,
        version: Int? = 1,
        timeout: TimeInterval? = nil
    ) throws -> CodexDesktopIPCResponseFrame {
        let requestID = UUID().uuidString
        let pendingRequest = PendingRequest(method: method)

        lock.lock()
        pendingRequests[requestID] = pendingRequest
        lock.unlock()

        try write(
            frame: .request(
                CodexDesktopIPCRequestFrame(
                    requestID: requestID,
                    method: method,
                    params: params,
                    sourceClientID: sourceClientID ?? clientID ?? "initializing-client",
                    targetClientID: targetClientID,
                    version: version
                )
            )
        )

        let waitTimeout = timeout ?? requestTimeout
        let didSignal = pendingRequest.semaphore.wait(timeout: .now() + waitTimeout)

        lock.lock()
        let completedRequest = pendingRequests.removeValue(forKey: requestID) ?? pendingRequest
        lock.unlock()

        guard didSignal == .success else {
            throw CodexDesktopIPCError.requestTimedOut(method)
        }

        guard let result = completedRequest.result else {
            throw CodexDesktopIPCError.invalidResponse
        }

        switch result {
        case let .success(response):
            if let error = response.error?.stringValue {
                throw CodexDesktopIPCError.responseError(error)
            }
            return response
        case let .failure(error):
            throw error
        }
    }

    private func readAvailableData() {
        guard socketFileDescriptor >= 0 else {
            return
        }

        var tempBuffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let tempBufferCount = tempBuffer.count
            let bytesRead = tempBuffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return 0
                }
                return Darwin.read(socketFileDescriptor, baseAddress, tempBufferCount)
            }
            if bytesRead > 0 {
                buffer.append(contentsOf: tempBuffer.prefix(bytesRead))

                do {
                    let frames = try CodexDesktopIPCCodec.decodeFrames(from: &buffer)
                    frames.forEach(handleFrame)
                } catch {
                    handleSocketTermination(reason: error.localizedDescription)
                    return
                }
            } else if bytesRead == 0 {
                handleSocketTermination(reason: CodexDesktopIPCError.disconnected.localizedDescription)
                return
            } else {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                handleSocketTermination(reason: String(cString: strerror(errno)))
                return
            }
        }
    }

    private func handleFrame(_ frame: CodexDesktopIPCFrame) {
        if case let .response(response) = frame {
            lock.lock()
            let pendingRequest = pendingRequests[response.requestID]
            lock.unlock()

            if let pendingRequest {
                pendingRequest.result = .success(response)
                pendingRequest.semaphore.signal()
                return
            }
        }

        onFrame?(frame)
    }

    private func handleSocketTermination(reason: String?) {
        let currentFD = socketFileDescriptor
        socketFileDescriptor = -1
        readSource?.cancel()
        readSource = nil
        clientID = nil
        buffer.removeAll(keepingCapacity: false)
        rejectPendingRequests(with: CodexDesktopIPCError.disconnected)

        if currentFD >= 0 {
            shutdown(currentFD, SHUT_RDWR)
            close(currentFD)
        }

        onDisconnect?(reason)
    }

    private func rejectPendingRequests(with error: Error) {
        lock.lock()
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        lock.unlock()

        for request in requests {
            request.result = .failure(error)
            request.semaphore.signal()
        }
    }

    private func write(frame: CodexDesktopIPCFrame) throws {
        guard socketFileDescriptor >= 0 else {
            throw CodexDesktopIPCError.disconnected
        }

        let data = try CodexDesktopIPCCodec.encode(frame: frame)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            var offset = 0
            while offset < data.count {
                let bytesWritten = Darwin.write(socketFileDescriptor, baseAddress.advanced(by: offset), data.count - offset)
                if bytesWritten < 0 {
                    throw CodexDesktopIPCError.disconnected
                }
                offset += bytesWritten
            }
        }
    }
}

private final class PendingRequest: @unchecked Sendable {
    let method: String
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<CodexDesktopIPCResponseFrame, Error>?

    init(method: String) {
        self.method = method
    }
}
