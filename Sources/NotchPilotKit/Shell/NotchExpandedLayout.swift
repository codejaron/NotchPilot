import CoreGraphics

enum NotchExpandedLayout {
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 10
    static let headerHeight: CGFloat = 32
    static let headerContentSpacing: CGFloat = 8
    static let safeHorizontalPadding: CGFloat = 27
    static let pluginTabSize = CGSize(width: 34, height: 24)
    static let pluginTabIconSize: CGFloat = 13
    static let settingsButtonSize: CGFloat = 24
    static let settingsIconSize: CGFloat = 10

    static func pluginViewportHeight(forDisplayHeight displayHeight: CGFloat) -> CGFloat {
        max(
            0,
            displayHeight - topPadding - headerHeight - headerContentSpacing - bottomPadding
        )
    }
}
