import XCTest
@testable import NotchPilotKit

final class AppLocalizationTests: XCTestCase {
    func testStringCatalogReadsCompiledStringsBundles() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        try writeStringsFile(
            bundleURL: bundleURL,
            language: .zhHans,
            values: [
                "general": "通用",
                "language": "语言",
            ]
        )
        try writeStringsFile(
            bundleURL: bundleURL,
            language: .english,
            values: [
                "general": "General",
                "language": "Language",
            ]
        )

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        let catalog = AppStringCatalog(bundle: bundle)

        XCTAssertEqual(catalog.text(for: .general, language: .zhHans), "通用")
        XCTAssertEqual(catalog.text(for: .language, language: .english), "Language")
    }

    func testStringCatalogContainsEveryStaticTextKeyInBothLanguages() {
        for key in AppTextKey.allCases {
            XCTAssertTrue(
                AppStringCatalog.shared.hasTranslation(for: key, language: .zhHans),
                "Missing zh-Hans catalog translation for \(key.rawValue)"
            )
            XCTAssertTrue(
                AppStringCatalog.shared.hasTranslation(for: key, language: .english),
                "Missing en catalog translation for \(key.rawValue)"
            )
        }
    }

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
        XCTAssertEqual(
            AppStrings.codexOptionTitle(
                "Allow for this chat",
                language: .zhHans
            ),
            "仅在此对话中允许"
        )
        XCTAssertEqual(
            AppStrings.codexOptionTitle(
                "Always allow",
                language: .zhHans
            ),
            "始终允许"
        )
        XCTAssertEqual(AppStrings.codexButtonTitle("Allow", language: .zhHans), "允许")
        XCTAssertEqual(AppStrings.codexButtonTitle("Cancel", language: .zhHans), "取消")
        XCTAssertEqual(AppStrings.codexOptionTitle("Cancel", language: .zhHans), "取消")
    }

    func testClaudePermissionActionTitlesPassThroughVerbatim() {
        XCTAssertEqual(
            AppStrings.approvalActionTitle(
                "Yes, and don't ask again for Web Search commands in /Users/jaron/project",
                id: "claude-allow-persist",
                language: .zhHans
            ),
            "Yes, and don't ask again for Web Search commands in /Users/jaron/project"
        )
        XCTAssertEqual(
            AppStrings.approvalActionTitle(
                "Yes",
                id: "claude-allow",
                language: .zhHans
            ),
            "Yes"
        )
        XCTAssertEqual(
            AppStrings.approvalActionTitle(
                "No",
                id: "claude-deny",
                language: .zhHans
            ),
            "No"
        )
    }

    func testSystemMonitorLabelsResolveInBothLanguages() {
        XCTAssertEqual(AppStrings.systemMonitorMetricTitle(.memory, language: .zhHans), "内存")
        XCTAssertEqual(AppStrings.systemMonitorMetricTitle(.memory, language: .english), "Memory")
        XCTAssertEqual(AppStrings.systemMonitorBlockTitle(.network, language: .zhHans), "网络")
        XCTAssertEqual(AppStrings.systemMonitorBlockTitle(.network, language: .english), "Network")
    }

    private func writeStringsFile(
        bundleURL: URL,
        language: AppLanguage,
        values: [String: String]
    ) throws {
        let languageDirectory = bundleURL.appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: languageDirectory, withIntermediateDirectories: true)

        let contents = values
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\" = \"\($0.value)\";" }
            .joined(separator: "\n")

        try contents.write(
            to: languageDirectory.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
    }
}
