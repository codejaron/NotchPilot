import AppKit
import CoreGraphics

enum ScreenDescriptorFactory {
    static func descriptor(
        for screen: NSScreen,
        includeClosedNotchSize: Bool
    ) -> ScreenDescriptor? {
        guard let id = screenID(for: screen) else {
            return nil
        }

        return descriptor(
            id: id,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            isPrimary: screen == NSScreen.screens.first,
            includeClosedNotchSize: includeClosedNotchSize,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            safeAreaTopInset: screen.safeAreaInsets.top
        )
    }

    static func descriptor(
        id: String,
        frame: CGRect,
        visibleFrame: CGRect,
        isPrimary: Bool,
        includeClosedNotchSize: Bool,
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil,
        safeAreaTopInset: CGFloat = 0
    ) -> ScreenDescriptor {
        let closedNotchSize = includeClosedNotchSize
            ? NotchSizing.closedCompactSize(
                screenFrame: frame,
                auxiliaryTopLeftArea: auxiliaryTopLeftArea,
                auxiliaryTopRightArea: auxiliaryTopRightArea,
                safeAreaTopInset: safeAreaTopInset,
                menuBarHeight: frame.maxY - visibleFrame.maxY
            )
            : nil

        return ScreenDescriptor(
            id: id,
            frame: frame,
            isPrimary: isPrimary,
            closedNotchSize: closedNotchSize
        )
    }

    static func screenID(for screen: NSScreen) -> String? {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(screenNumber.uint32Value)
        }

        return screen.localizedName
    }
}
