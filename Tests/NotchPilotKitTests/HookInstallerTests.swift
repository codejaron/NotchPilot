import XCTest
@testable import NotchPilotKit

final class HookInstallerTests: XCTestCase {
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHomeURL)
        tempHomeURL = nil
    }

    func testInstallClaudeHooksPreservesExistingEntriesAndAddsManagedCommand() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "theme": "dark",
              "hooks": {
                "Stop": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "echo keep"
                      }
                    ]
                  }
                ]
              }
            }
            """.utf8
        ).write(to: settingsURL)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        try installer.installClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: settingsURL)
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let stopEntries = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let commands = stopEntries.flatMap(commandStrings(in:))
        XCTAssertEqual(stopEntries.count, 2)
        XCTAssertTrue(commands.contains { $0.contains("/tmp/notch-bridge.py") && $0.contains("--host claude") })
    }

    func testUninstallClaudeHooksRemovesOnlyManagedEntries() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "hooks": {
                "Stop": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "echo keep"
                      }
                    ]
                  },
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
        ).write(to: settingsURL)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        try installer.uninstallClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: settingsURL)
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let stopEntries = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopEntries.count, 1)
        XCTAssertTrue(serializedJSONString(json).contains("echo keep"))
        XCTAssertFalse(serializedJSONString(json).contains("notch-bridge.py"))
    }

    func testInstallBridgeScriptCopiesFileIntoNotchPilotDirectory() throws {
        let sourceURL = tempHomeURL.appendingPathComponent("notch-bridge.py")
        try "#!/usr/bin/env python3\nprint('ok')\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        let installedPath = try installer.installBridgeScript(fromBundle: sourceURL.path)

        XCTAssertEqual(installedPath, tempHomeURL.appendingPathComponent(".notchpilot/notch-bridge.py").path)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installedPath))
    }

    func testInstallClaudeHooksAddsUserPromptSubmitEntry() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        try installer.installClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: claudeDirectory.appendingPathComponent("settings.json"))
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let promptEntries = try XCTUnwrap(hooks["UserPromptSubmit"] as? [[String: Any]])

        XCTAssertTrue(promptEntries.flatMap(commandStrings(in:)).contains { $0.contains("--host claude") })
    }

    func testInstallClaudeHooksRegistersPermissionRequestAndPreToolUseObserver() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        try installer.installClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: claudeDirectory.appendingPathComponent("settings.json"))
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let permissionEntries = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        let preToolEntries = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertTrue(permissionEntries.flatMap(commandStrings(in:)).contains { $0.contains("--host claude") })
        XCTAssertTrue(preToolEntries.flatMap(commandStrings(in:)).contains { $0.contains("--host claude") })
    }

    func testInstallClaudeHooksUsesShortPermissionRequestTimeoutToBoundStuckApprovals() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        try installer.installClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: claudeDirectory.appendingPathComponent("settings.json"))
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let permissionEntries = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        let permissionHooks = permissionEntries
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
        let timeouts = permissionHooks.compactMap { $0["timeout"] as? Int }

        XCTAssertEqual(timeouts, [30])
    }

    func testInstallClaudeHooksReplacesManagedPreToolUseEntries() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "hooks": {
                "PreToolUse": [
                  {
                    "matcher": "*",
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
        ).write(to: settingsURL)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        try installer.installClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: settingsURL)
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let preToolEntries = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let preToolCommands = preToolEntries.flatMap(commandStrings(in:))
        XCTAssertEqual(preToolCommands.count, 1)
        XCTAssertTrue(preToolCommands.first?.contains("/tmp/notch-bridge.py") == true)
        XCTAssertNotNil(hooks["PermissionRequest"])
    }

    func testClaudeHooksNeedUpdateReturnsTrueWhenPreToolUseObserverMissing() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "hooks": {
                "PermissionRequest": [
                  {
                    "matcher": "*",
                    "hooks": [
                      {
                        "type": "command",
                        "command": "\\"/tmp/notch-bridge.py\\" --host claude"
                      }
                    ]
                  }
                ],
                "PostToolUse": [
                  {
                    "matcher": "*",
                    "hooks": [
                      {
                        "type": "command",
                        "command": "\\"/tmp/notch-bridge.py\\" --host claude"
                      }
                    ]
                  }
                ],
                "SessionStart": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "\\"/tmp/notch-bridge.py\\" --host claude"
                      }
                    ]
                  }
                ],
                "Stop": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "\\"/tmp/notch-bridge.py\\" --host claude"
                      }
                    ]
                  }
                ],
                "UserPromptSubmit": [
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
        ).write(to: settingsURL)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)

        XCTAssertTrue(installer.claudeHooksInstalled(bridgeScript: "/tmp/notch-bridge.py"))
        XCTAssertTrue(installer.claudeHooksNeedUpdate(bridgeScript: "/tmp/notch-bridge.py"))
    }

    func testClaudeHooksNeedUpdateDetectsIncompleteManagedHookSet() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "hooks": {
                "PreToolUse": [
                  {
                    "matcher": "*",
                    "hooks": [
                      {
                        "type": "command",
                        "command": "\\"/tmp/notch-bridge.py\\" --host claude"
                      }
                    ]
                  }
                ],
                "UserPromptSubmit": [
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
        ).write(to: settingsURL)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)

        XCTAssertTrue(installer.claudeHooksInstalled(bridgeScript: "/tmp/notch-bridge.py"))
        XCTAssertTrue(installer.claudeHooksNeedUpdate(bridgeScript: "/tmp/notch-bridge.py"))
    }

    func testClaudeHooksNeedUpdateReturnsTrueWhenPromptHookMissing() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
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
        ).write(to: settingsURL)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)

        XCTAssertTrue(installer.claudeHooksInstalled(bridgeScript: "/tmp/notch-bridge.py"))
        XCTAssertTrue(installer.claudeHooksNeedUpdate(bridgeScript: "/tmp/notch-bridge.py"))
    }

    /// Real-world failure mode: a user installed Claude hooks under an older
    /// NotchPilot that did not persist `bridge.scriptPath` in UserDefaults.
    /// Their on-disk bridge is now stale, but `synchronizeInstallationState`
    /// passes `bridgeScript: nil` to `claudeHooksNeedUpdate`, so the version
    /// check used to silently bail out and the settings panel would offer only
    /// "Remove Integration". The installer must look at the canonical path
    /// (`~/.notchpilot/notch-bridge.py`) as a fallback.
    func testClaudeHooksNeedUpdateFallsBackToCanonicalPathWhenScriptPathIsNil() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")

        // Hooks were installed by an older NotchPilot — the command refers to
        // the canonical location under ~/.notchpilot/, even though the script
        // file there is now stale.
        let canonicalBridgeURL = tempHomeURL.appendingPathComponent(".notchpilot/notch-bridge.py")
        try FileManager.default.createDirectory(
            at: canonicalBridgeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/usr/bin/env python3\nNOTCHPILOT_BRIDGE_VERSION = 3\n".write(
            to: canonicalBridgeURL, atomically: true, encoding: .utf8
        )

        let canonicalPath = canonicalBridgeURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        try Data(
            """
            {
              "hooks": {
                "PreToolUse": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "\\"\(canonicalPath)\\" --host claude" } ] }
                ],
                "PermissionRequest": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "\\"\(canonicalPath)\\" --host claude", "timeout": 30 } ] }
                ],
                "PostToolUse": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "\\"\(canonicalPath)\\" --host claude" } ] }
                ],
                "SessionStart": [
                  { "hooks": [ { "type": "command", "command": "\\"\(canonicalPath)\\" --host claude" } ] }
                ],
                "Stop": [
                  { "hooks": [ { "type": "command", "command": "\\"\(canonicalPath)\\" --host claude" } ] }
                ],
                "UserPromptSubmit": [
                  { "hooks": [ { "type": "command", "command": "\\"\(canonicalPath)\\" --host claude" } ] }
                ]
              }
            }
            """.utf8
        ).write(to: settingsURL)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)

        // Caller passes `nil` because `store.bridgeScriptPath` was never set.
        XCTAssertTrue(installer.claudeHooksInstalled(bridgeScript: nil))
        XCTAssertTrue(installer.claudeHooksNeedUpdate(bridgeScript: nil),
                      "Stale bridge at canonical path must be detected even when bridgeScriptPath is nil")
    }

    /// Regression guard for the bridge-version bump. When we bump
    /// `NOTCHPILOT_BRIDGE_VERSION` in the bundled `notch-bridge.py`, the
    /// corresponding needle in `HookInstaller.bridgeVersionNeedle` must move
    /// with it — otherwise the app would treat stale installed scripts as
    /// up-to-date and never re-deploy them. We simulate an old bridge file on
    /// disk and expect `claudeHooksNeedUpdate` to flag it.
    func testClaudeHooksNeedUpdateFlagsStaleBridgeScript() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let bridgeURL = tempHomeURL.appendingPathComponent("stale-notch-bridge.py")
        let bridgePath = bridgeURL.path
        let escapedBridgePath = bridgePath.replacingOccurrences(of: "\"", with: "\\\"")
        try Data(
            """
            {
              "hooks": {
                "PreToolUse": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "\\"\(escapedBridgePath)\\" --host claude" } ] }
                ],
                "PermissionRequest": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "\\"\(escapedBridgePath)\\" --host claude", "timeout": 30 } ] }
                ],
                "PostToolUse": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "\\"\(escapedBridgePath)\\" --host claude" } ] }
                ],
                "SessionStart": [
                  { "hooks": [ { "type": "command", "command": "\\"\(escapedBridgePath)\\" --host claude" } ] }
                ],
                "Stop": [
                  { "hooks": [ { "type": "command", "command": "\\"\(escapedBridgePath)\\" --host claude" } ] }
                ],
                "UserPromptSubmit": [
                  { "hooks": [ { "type": "command", "command": "\\"\(escapedBridgePath)\\" --host claude" } ] }
                ]
              }
            }
            """.utf8
        ).write(to: settingsURL)

        // Pretend the installed bridge script is still on the *previous* version.
        try "#!/usr/bin/env python3\nNOTCHPILOT_BRIDGE_VERSION = 3\n".write(
            to: bridgeURL, atomically: true, encoding: .utf8
        )

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        XCTAssertTrue(installer.claudeHooksInstalled(bridgeScript: bridgePath))
        XCTAssertTrue(installer.claudeHooksNeedUpdate(bridgeScript: bridgePath),
                      "An older bridge version on disk must be flagged for update")

        // Now upgrade the on-disk bridge to the current version — should clear.
        try "#!/usr/bin/env python3\nNOTCHPILOT_BRIDGE_VERSION = 4\n".write(
            to: bridgeURL, atomically: true, encoding: .utf8
        )
        XCTAssertFalse(installer.claudeHooksNeedUpdate(bridgeScript: bridgePath),
                       "A current bridge version must not be flagged for update")
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func serializedJSONString(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private func commandStrings(in entry: [String: Any]) -> [String] {
        let hooks = entry["hooks"] as? [[String: Any]] ?? []
        return hooks.compactMap { $0["command"] as? String }
    }
}
