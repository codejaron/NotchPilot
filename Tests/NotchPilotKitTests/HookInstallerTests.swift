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

    func testInstallClaudeHooksDoesNotRegisterPermissionRequestEvent() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let installer = HookInstaller(homeDirectoryURL: tempHomeURL)
        try installer.installClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: claudeDirectory.appendingPathComponent("settings.json"))
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        XCTAssertNil(hooks["PermissionRequest"])
    }

    func testInstallClaudeHooksRemovesStaleManagedPermissionRequestEntries() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "hooks": {
                "PermissionRequest": [
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
        try installer.installClaudeHooks(bridgeScript: "/tmp/notch-bridge.py")

        let json = try loadJSONObject(at: settingsURL)
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        XCTAssertNil(hooks["PermissionRequest"])
    }

    func testClaudeHooksNeedUpdateDetectsStalePermissionRequestEntry() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "hooks": {
                "PermissionRequest": [
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
