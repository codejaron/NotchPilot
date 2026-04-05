import XCTest
@testable import NotchPilotKit

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var tempHomeURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)

        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempHomeURL)
        tempHomeURL = nil
        defaults = nil
        suiteName = nil
    }

    func testSynchronizeInstallationStateSetsNeedUpdateFlags() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try Data(
            """
            {
              "hooks": {
                "Stop": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "\\"/tmp/notch-bridge.py\\" --host claude"
                      }
                    ]
                  }
                ]
              }
            }
            """.utf8
        ).write(to: claudeDirectory.appendingPathComponent("settings.json"))

        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
        store.bridgeScriptPath = "/tmp/notch-bridge.py"

        store.synchronizeInstallationState()

        XCTAssertTrue(store.claudeHookInstalled)
        XCTAssertTrue(store.claudeHooksNeedUpdate)
        XCTAssertFalse(store.codexHookInstalled)
        XCTAssertFalse(store.codexHooksNeedUpdate)
    }
}
