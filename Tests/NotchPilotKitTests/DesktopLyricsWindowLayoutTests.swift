import CoreGraphics
import XCTest
@testable import NotchPilotKit

final class DesktopLyricsWindowLayoutTests: XCTestCase {
    func testWindowFrameIsPinnedToVisibleFrameBottomCenter() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 944)

        let frame = DesktopLyricsWindowLayout.frame(in: visibleFrame, cardWidth: 420)

        XCTAssertEqual(frame.width, 420, accuracy: 0.1)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.1)
        XCTAssertGreaterThan(frame.minY, visibleFrame.minY)
        XCTAssertLessThan(frame.maxY, visibleFrame.maxY)
    }

    func testPresentationFrameUsesActualLyricWidthForShortLines() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let lyrics = TimedLyrics(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200,
            service: "cache",
            lines: [
                TimedLyricLine(timestamp: 0, text: "Short"),
                TimedLyricLine(timestamp: 10, text: "Next"),
            ]
        )
        let snapshot = MediaPlaybackSnapshot(
            source: .fromBundleIdentifier("com.spotify.client"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            currentTime: 1,
            duration: 200,
            playbackRate: 1,
            isPlaying: true,
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
        let presentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: .active(snapshot),
            lyrics: lyrics,
            at: Date(timeIntervalSince1970: 100)
        )

        let frame = DesktopLyricsWindowLayout.frame(
            in: visibleFrame,
            presentation: presentation,
            fontSize: 28
        )

        XCTAssertLessThan(frame.width, DesktopLyricsWindowLayout.maxCardWidth)
        XCTAssertLessThan(frame.width, 300)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.1)

        let oldWideFrame = DesktopLyricsWindowLayout.frame(in: visibleFrame, fontSize: 28)
        let pointInOldEmptySide = CGPoint(x: oldWideFrame.minX + 24, y: frame.midY)
        XCTAssertTrue(oldWideFrame.contains(pointInOldEmptySide))
        XCTAssertFalse(frame.contains(pointInOldEmptySide))
    }

    func testCurrentLineHighlightUsesFullLineWhenInlineTimingIsUnavailable() {
        let lineStartDate = Date(timeIntervalSince1970: 100)
        let plainLine = DesktopLyricsLineState(
            currentLine: "line",
            nextLine: nil,
            inlineTags: nil,
            lineStartDate: lineStartDate,
            nextLineStartDate: nil,
            lineDuration: 4
        )
        let singleTagLine = DesktopLyricsLineState(
            currentLine: "line",
            nextLine: nil,
            inlineTags: [.init(index: 0, timeOffset: 0)],
            lineStartDate: lineStartDate,
            nextLineStartDate: nil,
            lineDuration: 4
        )

        XCTAssertEqual(DesktopLyricsCurrentLineHighlightMode.resolve(lineState: plainLine), .fullLine)
        XCTAssertEqual(DesktopLyricsCurrentLineHighlightMode.resolve(lineState: singleTagLine), .fullLine)
    }

    func testCurrentLineHighlightUsesTimedProgressWhenInlineTimingIsDetailed() {
        let lineState = DesktopLyricsLineState(
            currentLine: "line",
            nextLine: nil,
            inlineTags: [
                .init(index: 0, timeOffset: 0),
                .init(index: 4, timeOffset: 2),
            ],
            lineStartDate: Date(timeIntervalSince1970: 100),
            nextLineStartDate: nil,
            lineDuration: 4
        )

        XCTAssertEqual(DesktopLyricsCurrentLineHighlightMode.resolve(lineState: lineState), .timedProgress)
    }

    func testActiveScreenResolverReturnsDescriptorContainingMouseLocation() {
        let descriptors = [
            ScreenDescriptor(
                id: "left",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                isPrimary: true,
                closedNotchSize: nil
            ),
            ScreenDescriptor(
                id: "right",
                frame: CGRect(x: 800, y: 0, width: 800, height: 600),
                isPrimary: false,
                closedNotchSize: nil
            ),
        ]

        let resolved = ActiveDesktopLyricsScreenResolver.resolve(
            mouseLocation: CGPoint(x: 1000, y: 300),
            descriptors: descriptors
        )

        XCTAssertEqual(resolved, "right")
    }

    @MainActor
    func testDesktopLyricsWindowHitTestingUsesItsOwnBounds() {
        let window = DesktopLyricsWindow()
        defer { window.close() }
        window.setFrame(CGRect(x: 100, y: 200, width: 220, height: 90), display: false)

        XCTAssertTrue(window.containsMouseLocation(CGPoint(x: 140, y: 240)))
        XCTAssertFalse(window.containsMouseLocation(CGPoint(x: 80, y: 240)))
        XCTAssertFalse(window.containsMouseLocation(CGPoint(x: 340, y: 240)))
    }

    func testActiveScreenResolverFallsBackToPreviousScreenAtMenuBarEdge() {
        let descriptors = [
            ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                isPrimary: true,
                closedNotchSize: nil
            ),
        ]

        XCTAssertEqual(
            ActiveDesktopLyricsScreenResolver.resolve(
                mouseLocation: CGPoint(x: 756, y: 944),
                descriptors: descriptors,
                fallbackID: "primary"
            ),
            "primary"
        )
        XCTAssertEqual(
            ActiveDesktopLyricsScreenResolver.resolve(
                mouseLocation: CGPoint(x: 756, y: 956),
                descriptors: descriptors,
                fallbackID: "primary"
            ),
            "primary"
        )
    }
}
