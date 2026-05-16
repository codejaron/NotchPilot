import XCTest
@testable import NotchPilotKit

final class AppLocalizationTests: XCTestCase {
    func testCoreSettingsStringsResolveInBothLanguages() {
        XCTAssertEqual(AppStrings.text(.general, language: .zhHans), "通用")
        XCTAssertEqual(AppStrings.text(.general, language: .english), "General")
        XCTAssertEqual(AppStrings.text(.language, language: .zhHans), "语言")
        XCTAssertEqual(AppStrings.text(.language, language: .english), "Language")
        XCTAssertEqual(AppStrings.text(.avoidDuplicateSounds, language: .zhHans), "避免重复提示音")
        XCTAssertEqual(AppStrings.text(.avoidDuplicateSounds, language: .english), "Avoid Duplicate Sounds")
    }

    func testDynamicStatusStringsResolveInBothLanguages() {
        XCTAssertEqual(
            AppStrings.connectionStatus(.notDetected, language: .zhHans),
            "未检测到"
        )
        XCTAssertEqual(
            AppStrings.connectionStatus(.notDetected, language: .english),
            "Not Detected"
        )
        XCTAssertEqual(
            AppStrings.codexOptionTitle(
                "Yes, and don't ask again for commands that start with `/bin/zsh -lc date`",
                language: .zhHans
            ),
            "是，且对于以后续内容开头的命令不再询问 /bin/zsh -lc date"
        )
    }

    func testClaudePermissionActionTitlesResolveInChinese() {
        XCTAssertEqual(
            AppStrings.approvalActionTitle(
                "Don't ask again this session",
                id: "claude-allow-persist",
                language: .zhHans
            ),
            "本会话不再询问"
        )
        XCTAssertEqual(
            AppStrings.approvalActionTitle(
                "Always allow in this project",
                id: "claude-allow-persist",
                language: .zhHans
            ),
            "此项目始终允许"
        )
        XCTAssertEqual(
            AppStrings.approvalActionTitle(
                "Accept edits this session",
                id: "claude-allow-persist",
                language: .zhHans
            ),
            "本会话自动接受编辑"
        )
        XCTAssertEqual(
            AppStrings.approvalActionTitle(
                "Always allow directory in this project",
                id: "claude-allow-persist",
                language: .zhHans
            ),
            "此项目始终允许目录"
        )
    }

    func testSystemMonitorLabelsResolveInBothLanguages() {
        XCTAssertEqual(AppStrings.systemMonitorMetricTitle(.memory, language: .zhHans), "内存")
        XCTAssertEqual(AppStrings.systemMonitorMetricTitle(.memory, language: .english), "Memory")
        XCTAssertEqual(AppStrings.systemMonitorBlockTitle(.network, language: .zhHans), "网络")
        XCTAssertEqual(AppStrings.systemMonitorBlockTitle(.network, language: .english), "Network")
    }

    func testNotificationsClearAllLabelResolvesInBothLanguages() {
        XCTAssertEqual(AppStrings.text(.notificationsMarkAllRead, language: .zhHans), "全部已读")
        XCTAssertEqual(AppStrings.text(.notificationsMarkAllRead, language: .english), "Mark all read")
    }
}
