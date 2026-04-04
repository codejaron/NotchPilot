import Foundation

public struct BridgeSocketConfiguration: Sendable {
    public let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public static let `default` = BridgeSocketConfiguration(socketPath: "/tmp/notchpilot.sock")
}

public enum UnixDomainSocketServerError: Error {
    case unableToCreateSocket
    case invalidSocketPath
    case bindFailed(code: Int32)
    case listenFailed(code: Int32)
}

public final class UnixDomainSocketServer: @unchecked Sendable {
    public typealias FrameHandler = @Sendable (BridgeFrame, @escaping @Sendable (Data) -> Void) -> Void
    public typealias DisconnectHandler = @Sendable (String) -> Void

    private let socketPath: String
    private let listenerQueue = DispatchQueue(label: "NotchPilot.UnixDomainSocketServer.listener")

    private var serverFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var onFrame: FrameHandler?
    private var onDisconnect: DisconnectHandler?
    private var activeConnections: [UUID: ClientConnection] = [:]
    private let activeConnectionsLock = NSLock()

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit {
        stop()
    }

    public func start(onFrame: @escaping FrameHandler, onDisconnect: @escaping DisconnectHandler) throws {
        stop()

        self.onFrame = onFrame
        self.onDisconnect = onDisconnect

        unlink(socketPath)

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw UnixDomainSocketServerError.unableToCreateSocket
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxLength else {
            close(fileDescriptor)
            throw UnixDomainSocketServerError.invalidSocketPath
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

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                bind(fileDescriptor, addressPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            let errorCode = errno
            close(fileDescriptor)
            throw UnixDomainSocketServerError.bindFailed(code: errorCode)
        }

        guard listen(fileDescriptor, SOMAXCONN) == 0 else {
            let errorCode = errno
            close(fileDescriptor)
            throw UnixDomainSocketServerError.listenFailed(code: errorCode)
        }

        serverFileDescriptor = fileDescriptor

        let acceptSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: listenerQueue)
        acceptSource.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        acceptSource.setCancelHandler {
            close(fileDescriptor)
        }
        acceptSource.resume()

        self.acceptSource = acceptSource
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        activeConnectionsLock.lock()
        activeConnections.removeAll()
        activeConnectionsLock.unlock()

        if serverFileDescriptor >= 0 {
            shutdown(serverFileDescriptor, SHUT_RDWR)
            close(serverFileDescriptor)
            serverFileDescriptor = -1
        }

        unlink(socketPath)
    }

    private func acceptPendingConnections() {
        while true {
            let clientFileDescriptor = accept(serverFileDescriptor, nil, nil)
            if clientFileDescriptor < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                return
            }

            let connectionID = UUID()
            let connection = ClientConnection(
                fileDescriptor: clientFileDescriptor,
                onFrame: onFrame,
                onDisconnect: onDisconnect,
                onClosed: { [weak self] in
                    self?.removeConnection(id: connectionID)
                }
            )
            activeConnectionsLock.lock()
            activeConnections[connectionID] = connection
            activeConnectionsLock.unlock()
            connection.start()
        }
    }

    private func removeConnection(id: UUID) {
        activeConnectionsLock.lock()
        activeConnections.removeValue(forKey: id)
        activeConnectionsLock.unlock()
    }
}

private final class ClientConnection: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let onFrame: UnixDomainSocketServer.FrameHandler?
    private let onDisconnect: UnixDomainSocketServer.DisconnectHandler?
    private let onClosed: @Sendable () -> Void
    private let queue = DispatchQueue(label: "NotchPilot.UnixDomainSocketServer.client")

    private var disconnectSource: DispatchSourceRead?
    private var isClosed = false
    private var requestID: String?

    init(
        fileDescriptor: Int32,
        onFrame: UnixDomainSocketServer.FrameHandler?,
        onDisconnect: UnixDomainSocketServer.DisconnectHandler?,
        onClosed: @escaping @Sendable () -> Void
    ) {
        self.fileDescriptor = fileDescriptor
        self.onFrame = onFrame
        self.onDisconnect = onDisconnect
        self.onClosed = onClosed
    }

    deinit {
        closeConnection()
    }

    func start() {
        queue.async { [weak self] in
            self?.readFrame()
        }
    }

    private func readFrame() {
        guard let line = readLineFromSocket() else {
            closeConnection()
            return
        }

        let decoder = JSONDecoder()
        guard let data = line.data(using: .utf8), let frame = try? decoder.decode(BridgeFrame.self, from: data) else {
            respond(Data("{}".utf8))
            return
        }

        requestID = frame.requestID
        beginDisconnectMonitoring()
        onFrame?(frame, { [weak self] response in
            self?.respond(response)
        })
    }

    private func beginDisconnectMonitoring() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.peekForDisconnect()
        }
        source.setCancelHandler {}
        source.resume()
        disconnectSource = source
    }

    private func peekForDisconnect() {
        var buffer = [UInt8](repeating: 0, count: 1)
        let result = recv(fileDescriptor, &buffer, 1, MSG_PEEK)
        if result == 0 {
            let currentRequestID = requestID
            closeConnection()
            if let currentRequestID {
                onDisconnect?(currentRequestID)
            }
        }
    }

    private func readLineFromSocket() -> String? {
        var buffer = Data()
        var byte: UInt8 = 0

        while true {
            let result = read(fileDescriptor, &byte, 1)
            if result <= 0 {
                break
            }

            if byte == 10 {
                break
            }

            buffer.append(byte)
        }

        guard buffer.isEmpty == false else {
            return nil
        }

        return String(data: buffer, encoding: .utf8)
    }

    private func respond(_ data: Data) {
        queue.async { [weak self] in
            guard let self, self.isClosed == false else {
                return
            }

            self.disconnectSource?.cancel()
            self.disconnectSource = nil

            var responseData = data
            responseData.append(0x0A)
            responseData.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }
                _ = write(self.fileDescriptor, baseAddress, rawBuffer.count)
            }

            self.closeConnection()
        }
    }

    private func closeConnection() {
        guard isClosed == false else {
            return
        }

        isClosed = true
        disconnectSource?.cancel()
        disconnectSource = nil
        shutdown(fileDescriptor, SHUT_RDWR)
        close(fileDescriptor)
        onClosed()
    }
}
