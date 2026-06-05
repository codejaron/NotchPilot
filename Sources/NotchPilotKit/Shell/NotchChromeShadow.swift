import CoreGraphics

enum NotchChromeShadow {
    struct Layer: Equatable {
        let opacity: Double
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        var horizontalRasterExtent: CGFloat {
            abs(x) + (radius * NotchChromeShadow.rasterSpreadMultiplier)
        }

        var bottomRasterExtent: CGFloat {
            max(0, y) + (radius * NotchChromeShadow.rasterSpreadMultiplier)
        }
    }

    static let ambientLayer = Layer(opacity: 0.34, radius: 8, x: 0, y: 5)
    static let depthLayer = Layer(opacity: 0.46, radius: 13, x: 0, y: 9)

    static let layers = [ambientLayer, depthLayer]
    static let rasterSpreadMultiplier: CGFloat = 3
    static let rasterSafetyPadding: CGFloat = 24

    static var requiredHorizontalInset: CGFloat {
        ceil((layers.map(\.horizontalRasterExtent).max() ?? 0) + rasterSafetyPadding)
    }

    static var requiredBottomInset: CGFloat {
        ceil((layers.map(\.bottomRasterExtent).max() ?? 0) + rasterSafetyPadding)
    }
}
