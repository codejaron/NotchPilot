import CoreGraphics
import Foundation

public enum NotchSizing {
    public static let fallbackCompactSize = CGSize(width: 185, height: 32)

    public static func closedCompactSize(
        screenFrame: CGRect,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        safeAreaTopInset: CGFloat,
        menuBarHeight: CGFloat
    ) -> CGSize {
        var notchWidth = fallbackCompactSize.width
        var notchHeight = fallbackCompactSize.height

        if
            let auxiliaryTopLeftArea,
            let auxiliaryTopRightArea,
            auxiliaryTopLeftArea.width > 0,
            auxiliaryTopRightArea.width > 0
        {
            let computedWidth = screenFrame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width + 4
            if computedWidth > 0 {
                notchWidth = computedWidth
            }
        }

        if safeAreaTopInset > 0 {
            notchHeight = safeAreaTopInset
        } else if menuBarHeight > 0 {
            notchHeight = menuBarHeight
        }

        return CGSize(width: notchWidth, height: max(1, notchHeight))
    }
}
