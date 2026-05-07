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
        XCTAssertEqual(store.systemMonitorSneakConfiguration.mode, .pinnedReactive)
        XCTAssertEqual(store.systemMonitorSneakConfiguration.leftMetrics, [.cpu])
        XCTAssertEqual(store.systemMonitorSneakConfiguration.rightMetrics, [.network])
        XCTAssertEqual(
            store.systemMonitorSneakConfiguration.reactiveMetrics,
            [.memory, .temperature, .battery, .disk]
        )

        store.systemMonitorSneakPreviewEnabled = false
        store.systemMonitorSneakConfiguration = SystemMonitorSneakConfiguration(
            mode: .alwaysOn,
            left: [.disk],
            right: [.battery, .network],
            reactive: [.cpu, .temperature]
        )

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
        XCTAssertFalse(reloadedStore.systemMonitorSneakPreviewEnabled)
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.mode, .alwaysOn)
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.leftMetrics, [.disk])
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.rightMetrics, [.battery, .network])
        XCTAssertEqual(reloadedStore.systemMonitorSneakConfiguration.reactiveMetrics, [.cpu, .temperature])
    }

    @MainActor
    func testSystemMonitorAlertThresholdsDefaultToCatalogAndPersistChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertEqual(store.systemMonitorAlertThresholds, SystemMonitorAlertThresholds.default)

        store.systemMonitorAlertThresholds = store.systemMonitorAlertThresholds
            .setting(60, for: .cpu)
            .setting(40, for: .battery)
            .setting(75, for: .temperature)

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )
        XCTAssertEqual(reloadedStore.systemMonitorAlertThresholds.cpuPercent, 60)
        XCTAssertEqual(reloadedStore.systemMonitorAlertThresholds.batteryPercent, 40)
        XCTAssertEqual(reloadedStore.systemMonitorAlertThresholds.temperatureCelsius, 75)
        // Untouched metrics still match the catalog default.
        XCTAssertEqual(
            reloadedStore.systemMonitorAlertThresholds.networkMBps,
            SystemMonitorAlertThresholds.default.networkMBps
        )
    }

    @MainActor
    func testSystemMonitorAlertThresholdsClampOutOfRangeValuesOnReload() {
        defaults.set(999, forKey: "systemMonitor.alertThreshold.cpu")
        defaults.set(-50, forKey: "systemMonitor.alertThreshold.battery")

        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertEqual(
            store.systemMonitorAlertThresholds.cpuPercent,
            SystemMonitorAlertThresholds.cpuPercentRange.upperBound
        )
        XCTAssertEqual(
            store.systemMonitorAlertThresholds.batteryPercent,
            SystemMonitorAlertThresholds.batteryPercentRange.lowerBound
        )
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

    @MainActor
    func testInterfaceLanguageDefaultsToChineseAndPersistsChanges() {
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertEqual(store.interfaceLanguage, .zhHans)

        store.interfaceLanguage = .english

        let reloadedStore = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertEqual(reloadedStore.interfaceLanguage, .english)
    }

    @MainActor
    func testInvalidPersistedInterfaceLanguageFallsBackToChinese() {
        defaults.set("fr", forKey: "app.interfaceLanguage")

        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL
        )

        XCTAssertEqual(store.interfaceLanguage, .zhHans)
    }

    @MainActor
    func testLaunchAtLoginInitialStateMirrorsController() {
        let controller = FakeLaunchAtLoginController(enabled: true)
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL,
            launchAtLoginController: controller
        )

        XCTAssertTrue(store.launchAtLoginEnabled)
    }

    @MainActor
    func testLaunchAtLoginToggleForwardsRegistrationToController() {
        let controller = FakeLaunchAtLoginController(enabled: false)
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL,
            launchAtLoginController: controller
        )

        store.launchAtLoginEnabled = true

        XCTAssertEqual(controller.setEnabledCalls, [true])
        XCTAssertTrue(controller.enabled)

        store.launchAtLoginEnabled = false

        XCTAssertEqual(controller.setEnabledCalls, [true, false])
        XCTAssertFalse(controller.enabled)
    }

    @MainActor
    func testLaunchAtLoginRevertsOnControllerError() {
        let controller = FakeLaunchAtLoginController(enabled: false)
        controller.errorToThrow = NSError(domain: "test", code: 1)
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL,
            launchAtLoginController: controller
        )

        store.launchAtLoginEnabled = true

        XCTAssertFalse(store.launchAtLoginEnabled)
        XCTAssertFalse(controller.enabled)
    }

    @MainActor
    func testRefreshLaunchAtLoginStateSyncsFromControllerWithoutCallingSetter() {
        let controller = FakeLaunchAtLoginController(enabled: false)
        let store = SettingsStore(
            defaults: defaults,
            fileManager: .default,
            homeDirectoryURL: tempHomeURL,
            launchAtLoginController: controller
        )

        controller.enabled = true
        store.refreshLaunchAtLoginState()

        XCTAssertTrue(store.launchAtLoginEnabled)
        XCTAssertTrue(controller.setEnabledCalls.isEmpty)
    }
}

@MainActor
private final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var enabled: Bool
    var errorToThrow: Error?
    private(set) var setEnabledCalls: [Bool] = []

    init(enabled: Bool = false) {
        self.enabled = enabled
    }

    func isEnabled() -> Bool { enabled }

    func setEnabled(_ value: Bool) throws {
        setEnabledCalls.append(value)
        if let errorToThrow {
            throw errorToThrow
        }
        enabled = value
    }
}
