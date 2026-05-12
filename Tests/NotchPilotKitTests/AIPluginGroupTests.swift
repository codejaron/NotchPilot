import XCTest
@testable import NotchPilotKit

@MainActor
final class AIPluginGroupTests: XCTestCase {

    func testAIPluginsFromMixedListReturnsOnlyAIPlugins() {
        let plugins: [any NotchPlugin] = [
            SystemMonitorPlugin(),
            ClaudePlugin(),
            CodexPlugin(),
        ]
        let aiPlugins = AIPluginGroup.aiPlugins(from: plugins)
        XCTAssertEqual(aiPlugins.count, 2)
        XCTAssertTrue(aiPlugins.contains(where: { $0.id == "claude" }))
        XCTAssertTrue(aiPlugins.contains(where: { $0.id == "codex" }))
    }

    func testNonAIPluginsFiltersOutAIPlugins() {
        let plugins: [any NotchPlugin] = [
            SystemMonitorPlugin(),
            ClaudePlugin(),
            NotificationsPlugin(),
            CodexPlugin(),
        ]
        let nonAIPlugins = AIPluginGroup.nonAIPlugins(from: plugins)
        XCTAssertEqual(nonAIPlugins.count, 2)
        XCTAssertTrue(nonAIPlugins.contains(where: { $0.id == "system-monitor" }))
        XCTAssertTrue(nonAIPlugins.contains(where: { $0.id == "notifications" }))
    }

    func testResolvedActivePluginIDMapsLegacyIDsToVirtualTabID() {
        XCTAssertEqual(AIPluginGroup.resolvedActivePluginID("claude"), "ai")
        XCTAssertEqual(AIPluginGroup.resolvedActivePluginID("codex"), "ai")
        XCTAssertEqual(AIPluginGroup.resolvedActivePluginID("devin"), "ai")
    }

    func testResolvedActivePluginIDPassesThroughOtherIDs() {
        XCTAssertEqual(AIPluginGroup.resolvedActivePluginID("system-monitor"), "system-monitor")
        XCTAssertEqual(AIPluginGroup.resolvedActivePluginID("media-playback"), "media-playback")
        XCTAssertEqual(AIPluginGroup.resolvedActivePluginID("notifications"), "notifications")
    }

    func testResolvedActivePluginIDPassesThroughNil() {
        XCTAssertNil(AIPluginGroup.resolvedActivePluginID(nil))
    }

    func testResolvedActivePluginIDIsIdempotentForVirtualTabID() {
        XCTAssertEqual(AIPluginGroup.resolvedActivePluginID("ai"), "ai")
    }

    func testDockOrderTakesMinimum() {
        let plugins: [any AIPluginRendering] = [ClaudePlugin(), CodexPlugin()]
        XCTAssertEqual(AIPluginGroup.dockOrder(of: plugins), 100)
    }

    func testDockOrderForEmptyReturnsIntMax() {
        XCTAssertEqual(AIPluginGroup.dockOrder(of: []), Int.max)
    }
}
