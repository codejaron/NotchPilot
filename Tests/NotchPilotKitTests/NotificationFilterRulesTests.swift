import XCTest
@testable import NotchPilotKit

final class NotificationFilterRulesTests: XCTestCase {
    private func makeNotification(bundleID: String = "com.tencent.xinWeChat") -> SystemNotification {
        SystemNotification(
            dbRecordID: 1,
            bundleIdentifier: bundleID,
            appDisplayName: "WeChat",
            title: "张三",
            subtitle: nil,
            body: "明天下午开会",
            deliveredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeRules(
        enabled: Bool = true,
        whitelist: Set<String> = ["com.tencent.xinWeChat"],
        respectDND: Bool = true,
        privacy: NotificationContentPrivacy = .full,
        dndActive: Bool = false
    ) -> NotificationFilterRules {
        NotificationFilterRules(
            enabled: enabled,
            whitelistedBundleIDs: whitelist,
            respectSystemDND: respectDND,
            contentPrivacy: privacy,
            isSystemDNDActive: { dndActive }
        )
    }

    func testDropsWhenPluginDisabled() {
        let rules = makeRules(enabled: false)
        guard case .drop = rules.evaluate(makeNotification()) else {
            return XCTFail("expected .drop")
        }
    }

    func testDropsWhenNotWhitelisted() {
        let rules = makeRules(whitelist: [])
        guard case .drop = rules.evaluate(makeNotification()) else {
            return XCTFail("expected .drop")
        }
    }

    func testRecordOnlyWhenDNDActiveAndRespected() {
        let rules = makeRules(dndActive: true)
        guard case .recordOnly = rules.evaluate(makeNotification()) else {
            return XCTFail("expected .recordOnly")
        }
    }

    func testPresentsWhenWhitelistedAndNoDND() {
        let rules = makeRules()
        guard case .present(let redacted) = rules.evaluate(makeNotification()) else {
            return XCTFail("expected .present")
        }
        XCTAssertEqual(redacted.body, "明天下午开会")
        XCTAssertEqual(redacted.title, "张三")
    }

    func testWhitelistMatchingIsCaseInsensitive() {
        let rules = makeRules(whitelist: ["com.tencent.xinwechat"])
        guard case .present = rules.evaluate(makeNotification(bundleID: "com.tencent.xinWeChat")) else {
            return XCTFail("expected .present")
        }
    }

    func testSenderOnlyPrivacyRedactsBody() {
        let rules = makeRules(privacy: .senderOnly)
        guard case .present(let redacted) = rules.evaluate(makeNotification()) else {
            return XCTFail("expected .present")
        }
        XCTAssertEqual(redacted.title, "张三")
        XCTAssertNil(redacted.body)
        XCTAssertNil(redacted.subtitle)
    }

    func testHiddenPrivacyMasksTitleAndBody() {
        let rules = makeRules(privacy: .hidden)
        guard case .present(let redacted) = rules.evaluate(makeNotification()) else {
            return XCTFail("expected .present")
        }
        XCTAssertNil(redacted.title)
        XCTAssertNil(redacted.body)
        XCTAssertNil(redacted.subtitle)
    }

    func testDNDIgnoredWhenRespectSystemDNDDisabled() {
        let rules = makeRules(respectDND: false, dndActive: true)
        guard case .present = rules.evaluate(makeNotification()) else {
            return XCTFail("expected .present")
        }
    }
}
