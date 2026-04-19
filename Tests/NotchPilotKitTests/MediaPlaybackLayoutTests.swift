import AppKit
import XCTest
@testable import NotchPilotKit

final class MediaPlaybackLayoutTests: XCTestCase {
    func testExpandedMediaLayoutFitsInsidePluginViewport() {
        let viewportHeight = NotchExpandedLayout.pluginViewportHeight(forDisplayHeight: 240)
        let requiredHeight = MediaPlaybackExpandedLayout.estimatedContentHeight(titleLineCount: 2)

        XCTAssertLessThanOrEqual(requiredHeight, viewportHeight)
    }

    func testExpandedMediaProgressChromeRemainsVisibleOnIslandBackground() {
        XCTAssertGreaterThanOrEqual(MediaPlaybackProgressChrome.trackHeight, 5)
        XCTAssertGreaterThanOrEqual(MediaPlaybackProgressChrome.restingThumbDiameter, 10)
        XCTAssertGreaterThanOrEqual(MediaPlaybackProgressChrome.inactiveTrackLuminance(onBackgroundLuminance: 0), 0.16)
        XCTAssertGreaterThanOrEqual(MediaPlaybackProgressChrome.filledTrackLuminance(onBackgroundLuminance: 0), 0.9)
        XCTAssertGreaterThanOrEqual(
            MediaPlaybackProgressChrome.filledTrackLuminance(onBackgroundLuminance: 0)
                - MediaPlaybackProgressChrome.inactiveTrackLuminance(onBackgroundLuminance: 0),
            0.7
        )
    }

    func testCompactMediaPreviewKeepsContentOutsideCameraClearance() {
        let compactWidth: CGFloat = 185
        let preferredWidth = MediaPlaybackCompactPreviewLayout.preferredWidth(forCompactWidth: compactWidth)

        XCTAssertEqual(
            preferredWidth,
            compactWidth
                + MediaPlaybackCompactPreviewLayout.artworkAccessoryWidth
                + MediaPlaybackCompactPreviewLayout.levelAccessoryWidth,
            accuracy: 0.01
        )
        XCTAssertGreaterThanOrEqual(
            MediaPlaybackCompactPreviewLayout.artworkAccessoryWidth,
            MediaPlaybackCompactPreviewLayout.edgePadding
                + MediaPlaybackCompactPreviewLayout.artworkSize
                + MediaPlaybackCompactPreviewLayout.cameraEdgeSpacing
        )
        XCTAssertGreaterThanOrEqual(
            MediaPlaybackCompactPreviewLayout.levelAccessoryWidth,
            MediaPlaybackCompactPreviewLayout.edgePadding
                + MediaPlaybackCompactPreviewLayout.levelIndicatorWidth
                + MediaPlaybackCompactPreviewLayout.cameraEdgeSpacing
        )
        XCTAssertGreaterThanOrEqual(MediaPlaybackCompactPreviewLayout.edgePadding, 10)
        XCTAssertLessThanOrEqual(preferredWidth - compactWidth, 85)
    }

    func testCompactMediaPreviewUsesCompactSpectrumSizing() {
        XCTAssertEqual(MediaPlaybackCompactPreviewLayout.levelIndicatorWidth, 16)
        XCTAssertEqual(MediaPlaybackCompactPreviewLayout.levelIndicatorHeight, 12)
        XCTAssertEqual(MediaPlaybackCompactPreviewLayout.levelBarWidth, 2)
        XCTAssertEqual(MediaPlaybackCompactPreviewLayout.levelBarSpacing, 2)
        XCTAssertEqual(MediaPlaybackCompactPreviewLayout.levelGradientWidth, 50)
        XCTAssertEqual(MediaPlaybackCompactPreviewLayout.levelAnimationInterval, 0.3, accuracy: 0.001)
    }

    func testCompactMediaPreviewDerivesSpectrumTintFromArtwork() throws {
        let artworkData = try Self.pngData(color: NSColor(calibratedRed: 0.9, green: 0.12, blue: 0.05, alpha: 1))
        let color = try XCTUnwrap(MediaPlaybackArtworkPalette.averageSRGBColor(from: artworkData))
        let srgb = try XCTUnwrap(color.usingColorSpace(.sRGB))

        XCTAssertGreaterThan(srgb.redComponent, 0.7)
        XCTAssertGreaterThan(srgb.redComponent, srgb.greenComponent * 2)
        XCTAssertGreaterThan(srgb.redComponent, srgb.blueComponent * 2)
    }

    private static func pngData(color: NSColor, size: Int = 4) throws -> Data {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: size,
                pixelsHigh: size,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
