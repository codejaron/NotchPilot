import AppKit
import Foundation

public struct SystemNotificationSettingsOpener {
    static let notificationsPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )!

    private let openURL: (URL) -> Bool

    public init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
    }

    @discardableResult
    public func openNotificationsPane() -> Bool {
        openURL(Self.notificationsPaneURL)
    }
}
