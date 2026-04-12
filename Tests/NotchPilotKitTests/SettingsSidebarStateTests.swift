import XCTest
@testable import NotchPilotKit

final class SettingsSidebarStateTests: XCTestCase {
    func testSelectingPluginsOverviewExpandsPluginsGroup() {
        var state = SettingsSidebarState(selectedPane: .general)

        state.selectPluginsOverview()

        XCTAssertTrue(state.isPluginsExpanded)
        XCTAssertEqual(state.selectedPane, .pluginsOverview)
    }

    func testSelectingPluginKeepsPluginsGroupExpanded() {
        var state = SettingsSidebarState(selectedPane: .general)

        state.selectPlugin(.codex)

        XCTAssertTrue(state.isPluginsExpanded)
        XCTAssertEqual(state.selectedPane, .plugin(.codex))
    }

    func testSettingsPluginIDsIncludeSystemMonitor() {
        XCTAssertEqual(SettingsPluginID.allCases, [.systemMonitor, .claude, .codex])
    }
}
