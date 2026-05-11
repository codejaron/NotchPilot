import XCTest
@testable import NotchPilotKit

final class SettingsSidebarStateTests: XCTestCase {
    func testDefaultSidebarStateSelectsGeneralPane() {
        let state = SettingsSidebarState()

        XCTAssertEqual(state.selectedPane, .general)
    }

    func testSelectingPluginSwitchesToPluginPane() {
        var state = SettingsSidebarState(selectedPane: .general)

        state.selectPlugin(.codex)

        XCTAssertEqual(state.selectedPane, .plugin(.codex))
    }

    func testSelectingGeneralReturnsToGeneralPane() {
        var state = SettingsSidebarState(selectedPane: .plugin(.claude))

        state.selectGeneral()

        XCTAssertEqual(state.selectedPane, .general)
    }

    func testSettingsPluginIDsIncludeSystemMonitor() {
        XCTAssertEqual(SettingsPluginID.allCases, [.systemMonitor, .notifications, .claude, .codex, .media])
    }

    func testPluginSidebarSubtitlesMatchNativeLayoutLabels() {
        XCTAssertEqual(SettingsPluginID.media.sidebarSubtitle, "媒体播放")
        XCTAssertEqual(SettingsPluginID.systemMonitor.sidebarSubtitle, "系统监控")
        XCTAssertEqual(SettingsPluginID.claude.sidebarSubtitle, "Claude 集成")
        XCTAssertEqual(SettingsPluginID.codex.sidebarSubtitle, "连接状态")
    }

    @MainActor
    func testSidebarUsesFixedPluginIconsAndBrandGlyphsForAIPlugins() {
        XCTAssertEqual(SettingsPluginID.systemMonitor.iconSystemName, "cpu")
        XCTAssertEqual(SettingsPluginID.media.iconSystemName, "music.note")
        XCTAssertNil(SettingsPluginID.systemMonitor.brandGlyph)
        XCTAssertNil(SettingsPluginID.media.brandGlyph)
        XCTAssertEqual(SettingsPluginID.claude.brandGlyph, .claude)
        XCTAssertEqual(SettingsPluginID.codex.brandGlyph, .codex)
    }

    func testClaudeStatusTextUsesUserFacingLabels() {
        XCTAssertEqual(
            ClaudeSettingsStatusText(detected: false, installed: false, needsUpdate: false).value,
            "未检测到"
        )
        XCTAssertEqual(
            ClaudeSettingsStatusText(detected: true, installed: false, needsUpdate: false).value,
            "未安装"
        )
        XCTAssertEqual(
            ClaudeSettingsStatusText(detected: true, installed: true, needsUpdate: true).value,
            "可更新"
        )
        XCTAssertEqual(
            ClaudeSettingsStatusText(detected: true, installed: true, needsUpdate: false).value,
            "已连接"
        )
    }

    func testCodexStatusTextUsesUserFacingLabels() {
        XCTAssertEqual(
            CodexSettingsStatusText(detected: false, connection: .notFound).value,
            "未检测到"
        )
        XCTAssertEqual(
            CodexSettingsStatusText(detected: true, connection: .disconnected).value,
            "未连接"
        )
        XCTAssertEqual(
            CodexSettingsStatusText(detected: true, connection: .connecting).value,
            "连接中"
        )
        XCTAssertEqual(
            CodexSettingsStatusText(detected: true, connection: .connected).value,
            "已连接"
        )
        XCTAssertEqual(
            CodexSettingsStatusText(
                detected: true,
                connection: .error(message: "desktop offline")
            ).value,
            "错误"
        )
    }
}
