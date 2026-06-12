import XCTest

final class BridgeResourceTests: XCTestCase {
    func testBridgeScriptResourceMatchesSourceCopy() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent("Bridge/notch-bridge.py")
        let resourceURL = repositoryRoot.appendingPathComponent("Sources/NotchPilotKit/Resources/notch-bridge.py")

        XCTAssertEqual(
            try Data(contentsOf: sourceURL),
            try Data(contentsOf: resourceURL)
        )
    }
}
