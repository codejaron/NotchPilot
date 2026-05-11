import XCTest
@testable import NotchPilotKit

final class SystemNotificationTests: XCTestCase {
    func testEquatableConsidersAllFields() {
        let base = SystemNotification(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            dbRecordID: 42,
            bundleIdentifier: "com.tencent.xinWeChat",
            appDisplayName: "WeChat",
            title: "张三",
            subtitle: nil,
            body: "明天下午开会",
            deliveredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let same = base
        XCTAssertEqual(base, same)

        let different = SystemNotification(
            id: base.id, dbRecordID: 99,
            bundleIdentifier: base.bundleIdentifier, appDisplayName: base.appDisplayName,
            title: base.title, subtitle: base.subtitle, body: base.body, deliveredAt: base.deliveredAt
        )
        XCTAssertNotEqual(base, different)
    }
}
