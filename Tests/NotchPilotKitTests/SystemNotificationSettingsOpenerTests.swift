import XCTest
@testable import NotchPilotKit

final class SystemNotificationSettingsOpenerTests: XCTestCase {
    func testOpenNotificationsPaneUsesSystemSettingsNotificationsURL() {
        var openedURLs: [URL] = []
        let opener = SystemNotificationSettingsOpener { url in
            openedURLs.append(url)
            return true
        }

        let opened = opener.openNotificationsPane()

        XCTAssertTrue(opened)
        XCTAssertEqual(
            openedURLs,
            [URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!]
        )
    }
}
