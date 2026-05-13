import CoreGraphics

enum NotchTabGestureIntent {
    static let minimumHorizontalDelta: CGFloat = 28
    static let horizontalDominanceRatio: CGFloat = 1.4

    static func direction(
        horizontalDelta: CGFloat,
        verticalDelta: CGFloat,
        minimumHorizontalDelta: CGFloat = Self.minimumHorizontalDelta,
        horizontalDominanceRatio: CGFloat = Self.horizontalDominanceRatio
    ) -> NotchTabNavigator.Direction? {
        let horizontalMagnitude = abs(horizontalDelta)
        guard horizontalMagnitude >= minimumHorizontalDelta else {
            return nil
        }

        let verticalMagnitude = abs(verticalDelta)
        guard horizontalMagnitude >= max(1, verticalMagnitude) * horizontalDominanceRatio else {
            return nil
        }

        return horizontalDelta < 0 ? .next : .previous
    }
}
