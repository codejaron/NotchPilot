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
                "Yes, and don't ask again for commands that start with `rm -rf`",
                language: .zhHans
            ),
            "是，且对于以 `rm -rf` 开头的命令不再询问"
        )
    }

    func testSystemMonitorLabelsResolveInBothLanguages() {
        XCTAssertEqual(AppStrings.systemMonitorMetricTitle(.memory, language: .zhHans), "内存")
        XCTAssertEqual(AppStrings.systemMonitorMetricTitle(.memory, language: .english), "Memory")
        XCTAssertEqual(AppStrings.systemMonitorBlockTitle(.network, language: .zhHans), "网络")
        XCTAssertEqual(AppStrings.systemMonitorBlockTitle(.network, language: .english), "Network")
    }
}
