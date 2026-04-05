import Foundation
import XCTest
@testable import NotchPilotKit

final class CodexDesktopIPCDiscoveryTests: XCTestCase {
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

    func testDiscoverSocketPathsSortsNewestFirstAndIgnoresOtherFiles() throws {
        let olderURL = tempDirectoryURL.appendingPathComponent("ipc-100.sock")
        let newerURL = tempDirectoryURL.appendingPathComponent("ipc-200.sock")
        let ignoredURL = tempDirectoryURL.appendingPathComponent("notes.txt")

        FileManager.default.createFile(atPath: olderURL.path, contents: Data())
        FileManager.default.createFile(atPath: newerURL.path, contents: Data())
        FileManager.default.createFile(atPath: ignoredURL.path, contents: Data())

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: olderURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerURL.path
        )

        let discovery = CodexDesktopIPCDiscovery(directoryURL: tempDirectoryURL)

        let discovered = try discovery.discoverSocketPaths()

        XCTAssertEqual(discovered.map { URL(fileURLWithPath: $0).lastPathComponent }, [
            "ipc-200.sock",
            "ipc-100.sock",
        ])
    }
}
