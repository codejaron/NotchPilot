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
            CodexPlugin(),
        ]
        let nonAIPlugins = AIPluginGroup.nonAIPlugins(from: plugins)
        XCTAssertEqual(nonAIPlugins.count, 1)
        XCTAssertTrue(nonAIPlugins.contains(where: { $0.id == "system-monitor" }))
    }

    func testDockOrderTakesMinimum() {
        let plugins: [any AIPluginRendering] = [ClaudePlugin(), CodexPlugin()]
        XCTAssertEqual(AIPluginGroup.dockOrder(of: plugins), 100)
    }

    func testDockOrderForEmptyReturnsIntMax() {
        XCTAssertEqual(AIPluginGroup.dockOrder(of: []), Int.max)
    }
}
