import XCTest
@testable import NotchPilotKit

final class UnixDomainSocketServerTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
    }

    func testDefaultSocketPathUsesUserPrivateNotchPilotDirectory() {
        let socketPath = BridgeSocketConfiguration.default.socketPath

        XCTAssertFalse(socketPath.hasPrefix("/tmp/"))
        XCTAssertTrue(socketPath.hasSuffix("/.notchpilot/notchpilot.sock"))
    }

    func testStartCreatesSocketWithOwnerOnlyPermissions() throws {
        let socketURL = tempDirectoryURL.appendingPathComponent("notchpilot.sock")
        let server = UnixDomainSocketServer(socketPath: socketURL.path)
        defer { server.stop() }

        try server.start(onFrame: { _, _ in }, onDisconnect: { _ in })

        let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testAcceptChecksPeerIdentityBeforeStartingConnection() throws {
        let socketURL = tempDirectoryURL.appendingPathComponent("notchpilot.sock")
        let verifierCalled = expectation(description: "peer verifier called")
        let server = UnixDomainSocketServer(
            socketPath: socketURL.path,
            peerValidator: { _ in
                verifierCalled.fulfill()
                return false
            }
        )
        defer { server.stop() }

        try server.start(
            onFrame: { _, _ in XCTFail("rejected peers must not deliver frames") },
            onDisconnect: { _ in }
        )

        let client = try connect(to: socketURL.path)
        defer { close(client) }

        wait(for: [verifierCalled], timeout: 1)
    }

    private func connect(to socketPath: String) throws -> Int32 {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fileDescriptor, 0)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = Array(socketPath.utf8)
        XCTAssertLessThan(pathBytes.count, maxLength)

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

        if result != 0 {
            let code = errno
            close(fileDescriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }

        return fileDescriptor
    }
}
