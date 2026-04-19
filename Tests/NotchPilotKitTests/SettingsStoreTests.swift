import XCTest
@testable import NotchPilotKit

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

    @MainActor
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
        XCTAssertEqual(
            store.codexDesktopConnection.status,
            store.codexDetected ? .disconnected : .notFound
        )
    }

    @MainActor
    func testCodexDetectedUsesDesktopBundleOrCodexHomeDirectory() throws {
        let applicationsDirectory = tempHomeURL.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: applicationsDirectory.appendingPathComponent("Codex.app", isDirectory: true),
            withIntermediateDirectories: true
        )

        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertTrue(store.codexDetected)
    }

    @MainActor
    func testApprovalSneakNotificationsDefaultToEnabledAndPersistChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertTrue(store.approvalSneakNotificationsEnabled)

        store.approvalSneakNotificationsEnabled = false

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
        XCTAssertFalse(reloadedStore.approvalSneakNotificationsEnabled)
    }

    @MainActor
    func testActivitySneakPreviewHiddenSettingDefaultsToFalseAndPersistsChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertFalse(store.activitySneakPreviewsHidden)

        store.activitySneakPreviewsHidden = true

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
        XCTAssertTrue(reloadedStore.activitySneakPreviewsHidden)
    }

    @MainActor
    func testSystemMonitorSneakSettingsDefaultToApprovedLayoutAndPersistChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertTrue(store.systemMonitorSneakPreviewEnabled)
        XCTAssertEqual(store.systemMonitorSneakConfiguration.leftMetrics, [.cpu, .memory])
        XCTAssertEqual(store.systemMonitorSneakConfiguration.rightMetrics, [.network, .temperature])

        store.systemMonitorSneakPreviewEnabled = false
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            left: [.disk],
            right: [.battery, .network]
        )

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
        XCTAssertFalse(reloadedStore.systemMonitorSneakPreviewEnabled)
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.leftMetrics, [.disk])
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.rightMetrics, [.battery, .network])
    }

    @MainActor
    func testSystemMonitorSneakSettingsAllowEmptySides() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(left: [], right: [])

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.leftMetrics, [])
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.rightMetrics, [])
    }

    @MainActor
    func testMediaPlaybackSettingsDefaultToEnabledAndPersistChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertTrue(store.mediaPlaybackEnabled)
        XCTAssertTrue(store.mediaPlaybackSneakPreviewEnabled)

        store.mediaPlaybackEnabled = false
        store.mediaPlaybackSneakPreviewEnabled = false

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertFalse(reloadedStore.mediaPlaybackEnabled)
        XCTAssertFalse(reloadedStore.mediaPlaybackSneakPreviewEnabled)
    }

    @MainActor
    func testPluginAvailabilitySettingsDefaultToEnabledAndPersistChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertTrue(store.systemMonitorEnabled)
        XCTAssertTrue(store.claudePluginEnabled)
        XCTAssertTrue(store.codexPluginEnabled)
        XCTAssertTrue(store.mediaPlaybackEnabled)

        store.systemMonitorEnabled = false
        store.claudePluginEnabled = false
        store.codexPluginEnabled = false
        store.mediaPlaybackEnabled = false

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertFalse(reloadedStore.systemMonitorEnabled)
        XCTAssertFalse(reloadedStore.claudePluginEnabled)
        XCTAssertFalse(reloadedStore.codexPluginEnabled)
        XCTAssertFalse(reloadedStore.mediaPlaybackEnabled)
    }

    @MainActor
    func testDesktopLyricsSettingDefaultsToDisabledAndPersistsChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertFalse(store.desktopLyricsEnabled)

        store.desktopLyricsEnabled = true

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertTrue(reloadedStore.desktopLyricsEnabled)
    }
}
