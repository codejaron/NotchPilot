import Darwin
import Foundation
import XCTest
@testable import NotchPilotKit

final class CodexDesktopMonitorTests: XCTestCase {
    func testCanHandleDiscoveryRequestRecognizesSupportedApprovalRequests() {
        let approvalRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1",
            method: "item/commandExecution/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let fileChangeRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1b",
            method: "item/fileChange/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let legacyExecRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1legacy",
            method: "execCommandApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let legacyPatchRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1patch",
            method: "applyPatchApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let permissionsRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-1c",
            method: "item/permissions/requestApproval",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )
        let nonApprovalRequest = CodexDesktopIPCRequestFrame(
            requestID: "req-2",
            method: "ide-context",
            params: [:],
            sourceClientID: "desktop-client",
            targetClientID: nil,
            version: 1
        )

        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(approvalRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(fileChangeRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(legacyExecRequest))
        XCTAssertTrue(CodexDesktopMonitor.canHandleDiscoveryRequest(legacyPatchRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(permissionsRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nonApprovalRequest))
        XCTAssertFalse(CodexDesktopMonitor.canHandleDiscoveryRequest(nil))
    }

    func testPerformingLiveCommandApprovalSendsThreadFollowerDecisionRequest() throws {
        let server = try TestCodexIPCServer()
        defer { server.stop() }

        let monitor = CodexDesktopMonitor(
            detector: CodexDesktopAppDetector(
                fileManager: .default,
                homeDirectoryURL: server.installedAppHomeDirectoryURL
            ),
            discovery: CodexDesktopIPCDiscovery(directoryURL: server.socketDirectoryURL),
            requestTimeout: 1
        )
        let surfaceSignal = DispatchSemaphore(value: 0)
        monitor.onSurfaceChanged = { surface in
            guard surface?.id == "codex-ipc-66" else { return }
            surfaceSignal.signal()
        }

        monitor.start()
        defer { monitor.stop() }

        let initializeFrame = try server.waitForRequest(method: "initialize")
        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: initializeFrame.requestID,
                    method: "initialize",
                    result: .object([
                        "clientId": .string("notchpilot-test-client"),
                    ]),
                    error: nil
                )
            )
        )

        try server.send(
            frame: .broadcast(
                CodexDesktopIPCBroadcastFrame(
                    method: "thread-stream-state-changed",
                    params: [
                        "conversationId": .string("conv-live-approval"),
                        "change": .object([
                            "type": .string("snapshot"),
                            "conversationState": .object([
                                "id": .string("conv-live-approval"),
                                "threadRuntimeStatus": .object([
                                    "type": .string("idle"),
                                ]),
                                "requests": .array([
                                    .object([
                                        "method": .string("item/commandExecution/requestApproval"),
                                        "id": .integer(66),
                                        "params": .object([
                                            "threadId": .string("conv-live-approval"),
                                            "reason": .string("Run date?"),
                                            "command": .string("/bin/zsh -lc date"),
                                            "availableDecisions": .array([
                                                .string("accept"),
                                                .string("decline"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ],
                    sourceClientID: "desktop-owner-client",
                    targetClientID: nil,
                    version: 1
                )
            )
        )

        XCTAssertEqual(surfaceSignal.wait(timeout: .now() + 2), .success)

        let performResult = BooleanBox()
        let performSignal = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            performResult.value = monitor.perform(action: .primary, on: "codex-ipc-66")
            performSignal.signal()
        }

        let outboundFrame = try server.waitForNextFrame()
        guard case let .request(request) = outboundFrame else {
            return XCTFail("expected approval decision request, got \(outboundFrame)")
        }

        XCTAssertEqual(request.method, "thread-follower-command-approval-decision")
        XCTAssertEqual(request.params["conversationId"]?.stringValue, "conv-live-approval")
        XCTAssertEqual(request.params["requestId"], .integer(66))
        XCTAssertEqual(request.params["decision"], .string("accept"))
        XCTAssertEqual(request.targetClientID, "desktop-owner-client")

        try server.send(
            frame: .response(
                CodexDesktopIPCResponseFrame(
                    requestID: request.requestID,
                    method: request.method,
                    result: .object([:]),
                    error: nil
                )
            )
        )

        XCTAssertEqual(performSignal.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(performResult.value)
    }
}

private final class BooleanBox: @unchecked Sendable {
    var value = false
}

private final class TestCodexIPCServer: @unchecked Sendable {
    let socketDirectoryURL: URL
    let socketPath: String
    let installedAppHomeDirectoryURL: URL

    private let queue = DispatchQueue(label: "NotchPilot.TestCodexIPCServer")
    private let semaphore = DispatchSemaphore(value: 0)
    private let fileManager = FileManager.default
    private let serverSocket: Int32
    private var clientSocket: Int32 = -1
    private var frames: [CodexDesktopIPCFrame] = []
    private let lock = NSLock()

    init() throws {
        let tempRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("np-\(UUID().uuidString.prefix(8))", isDirectory: true)
        socketDirectoryURL = tempRoot.appendingPathComponent("codex-ipc", isDirectory: true)
        installedAppHomeDirectoryURL = tempRoot
        socketPath = socketDirectoryURL.appendingPathComponent("ipc-test.sock").path

        try fileManager.createDirectory(at: socketDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: tempRoot.appendingPathComponent("Applications", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: tempRoot.appendingPathComponent("Applications/Codex.app", isDirectory: true),
            withIntermediateDirectories: true
        )

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxLength else {
            close(serverSocket)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG))
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
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(serverSocket, pointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(serverSocket)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }

        guard listen(serverSocket, 1) == 0 else {
            let code = errno
            close(serverSocket)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        if clientSocket >= 0 {
            shutdown(clientSocket, SHUT_RDWR)
            close(clientSocket)
            clientSocket = -1
        }
        shutdown(serverSocket, SHUT_RDWR)
        close(serverSocket)
        try? fileManager.removeItem(at: installedAppHomeDirectoryURL)
    }

    func send(frame: CodexDesktopIPCFrame) throws {
        let data = try CodexDesktopIPCCodec.encode(frame: frame)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            var offset = 0
            while offset < data.count {
                let bytesWritten = Darwin.write(clientSocket, baseAddress.advanced(by: offset), data.count - offset)
                if bytesWritten < 0 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                offset += bytesWritten
            }
        }
    }

    func waitForRequest(method: String, timeout: TimeInterval = 2) throws -> CodexDesktopIPCRequestFrame {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let request = nextFrame(timeout: 0.1).flatMap({ frame -> CodexDesktopIPCRequestFrame? in
                guard case let .request(request) = frame, request.method == method else {
                    return nil
                }
                return request
            }) {
                return request
            }
        }

        XCTFail("timed out waiting for request \(method)")
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
    }

    func waitForNextFrame(timeout: TimeInterval = 2) throws -> CodexDesktopIPCFrame {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let frame = nextFrame(timeout: 0.1) {
                return frame
            }
        }

        XCTFail("timed out waiting for next frame")
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
    }

    private func nextFrame(timeout: TimeInterval) -> CodexDesktopIPCFrame? {
        lock.lock()
        if frames.isEmpty == false {
            let frame = frames.removeFirst()
            lock.unlock()
            return frame
        }
        lock.unlock()

        _ = semaphore.wait(timeout: .now() + timeout)

        lock.lock()
        defer { lock.unlock() }
        guard frames.isEmpty == false else {
            return nil
        }
        return frames.removeFirst()
    }

    private func acceptLoop() {
        let acceptedSocket = Darwin.accept(serverSocket, nil, nil)
        guard acceptedSocket >= 0 else {
            return
        }

        clientSocket = acceptedSocket

        var buffer = Data()
        var tempBuffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let tempBufferCount = tempBuffer.count
            let bytesRead = tempBuffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return 0
                }
                return Darwin.read(acceptedSocket, baseAddress, tempBufferCount)
            }

            if bytesRead <= 0 {
                return
            }

            buffer.append(contentsOf: tempBuffer.prefix(bytesRead))

            do {
                let decodedFrames = try CodexDesktopIPCCodec.decodeFrames(from: &buffer)
                if decodedFrames.isEmpty == false {
                    lock.lock()
                    frames.append(contentsOf: decodedFrames)
                    lock.unlock()
                    for _ in decodedFrames {
                        semaphore.signal()
                    }
                }
            } catch {
                return
            }
        }
    }
}
