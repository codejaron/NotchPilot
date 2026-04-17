import XCTest
@testable import NotchPilotKit

final class PermissionRuleStoreTests: XCTestCase {
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

    func testAppendAllowRuleCreatesSettingsFileWhenMissing() throws {
        let store = PermissionRuleStore(homeDirectoryURL: tempHomeURL)

        try store.appendAllowRule(.tool("Edit"))

        let settingsURL = tempHomeURL.appendingPathComponent(".claude/settings.json")
        let root = try loadJSON(at: settingsURL)
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        let allow = try XCTUnwrap(permissions["allow"] as? [String])
        XCTAssertEqual(allow, ["Edit"])
    }

    func testAppendAllowRulePreservesUnrelatedRootFields() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "theme": "dark",
              "model": "claude-opus-4-7",
              "hooks": {
                "PreToolUse": [{"matcher": "*", "hooks": []}]
              }
            }
            """.utf8
        ).write(to: settingsURL)

        let store = PermissionRuleStore(homeDirectoryURL: tempHomeURL)
        try store.appendAllowRule(.bashPrefix("git status"))

        let root = try loadJSON(at: settingsURL)
        XCTAssertEqual(root["theme"] as? String, "dark")
        XCTAssertEqual(root["model"] as? String, "claude-opus-4-7")
        XCTAssertNotNil(root["hooks"])

        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["allow"] as? [String], ["Bash(git status:*)"])
    }

    func testAppendAllowRuleAppendsToExistingAllowList() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "permissions": {
                "allow": ["Read", "Glob"]
              }
            }
            """.utf8
        ).write(to: settingsURL)

        let store = PermissionRuleStore(homeDirectoryURL: tempHomeURL)
        try store.appendAllowRule(.webFetchDomain("example.com"))

        let root = try loadJSON(at: settingsURL)
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        let allow = try XCTUnwrap(permissions["allow"] as? [String])
        XCTAssertEqual(allow, ["Read", "Glob", "WebFetch(domain:example.com)"])
    }

    func testAppendAllowRuleIsIdempotent() throws {
        let store = PermissionRuleStore(homeDirectoryURL: tempHomeURL)

        try store.appendAllowRule(.mcp(server: "linear", tool: "create_issue"))
        try store.appendAllowRule(.mcp(server: "linear", tool: "create_issue"))
        try store.appendAllowRule(.mcp(server: "linear", tool: "create_issue"))

        let settingsURL = tempHomeURL.appendingPathComponent(".claude/settings.json")
        let root = try loadJSON(at: settingsURL)
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        let allow = try XCTUnwrap(permissions["allow"] as? [String])
        XCTAssertEqual(allow, ["mcp__linear__create_issue"])
    }

    func testAppendAllowRulePreservesOtherPermissionKeys() throws {
        let claudeDirectory = tempHomeURL.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "permissions": {
                "deny": ["Bash(rm:*)"],
                "ask": ["WebFetch"]
              }
            }
            """.utf8
        ).write(to: settingsURL)

        let store = PermissionRuleStore(homeDirectoryURL: tempHomeURL)
        try store.appendAllowRule(.tool("Edit"))

        let root = try loadJSON(at: settingsURL)
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["allow"] as? [String], ["Edit"])
        XCTAssertEqual(permissions["deny"] as? [String], ["Bash(rm:*)"])
        XCTAssertEqual(permissions["ask"] as? [String], ["WebFetch"])
    }

    func testHookResponseEncoderRoutesPersistRuleIntoStore() throws {
        let store = PermissionRuleStore(homeDirectoryURL: tempHomeURL)
        let encoder = HookResponseEncoder(permissionRuleStore: store)
        let decision = ApprovalDecision(
            behavior: .allow,
            persistRule: .bashPrefix("git status")
        )

        _ = try encoder.encode(decision: decision, for: .claude, eventType: .preToolUse)

        let settingsURL = tempHomeURL.appendingPathComponent(".claude/settings.json")
        let root = try loadJSON(at: settingsURL)
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["allow"] as? [String], ["Bash(git status:*)"])
    }

    private func loadJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
