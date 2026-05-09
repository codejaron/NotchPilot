import AppKit
import Combine
import CoreText
import SwiftUI

enum DesktopLyricsWindowLayout {
    static let maxCardWidth: CGFloat = 720
    static let cardHeight: CGFloat = 88
    static let horizontalPadding: CGFloat = 22
    static let bottomInset: CGFloat = 28

    static func cardHeight(fontSize: CGFloat) -> CGFloat {
        let currentLineHeight = ceil(fontSize * 1.25)
        let nextLineHeight = ceil(fontSize * 0.72 * 1.25)
        return currentLineHeight + nextLineHeight + 6 + 32
    }

    static func frame(in visibleFrame: CGRect, cardWidth: CGFloat? = nil, fontSize: CGFloat = 28) -> CGRect {
        let width = min(cardWidth ?? maxCardWidth, maxCardWidth)
        let height = cardHeight(fontSize: fontSize)
        return CGRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.minY + bottomInset,
            width: width,
            height: height
        )
    }
}

enum ActiveDesktopLyricsScreenResolver {
    static func resolve(mouseLocation: CGPoint, descriptors: [ScreenDescriptor]) -> String? {
        descriptors.first(where: { $0.frame.contains(mouseLocation) })?.id
    }
}

struct DesktopLyricsViewState: Equatable {
    let presentation: DesktopLyricsPresentation
    let isMouseHovering: Bool
    let highlightColor: Color
    let fontSize: CGFloat

    static let hidden = DesktopLyricsViewState(
        presentation: .hidden,
        isMouseHovering: false,
        highlightColor: .green,
        fontSize: 28
    )
}

@MainActor
final class DesktopLyricsWindowModel: ObservableObject {
    @Published private(set) var state: DesktopLyricsViewState = .hidden

    func update(_ next: DesktopLyricsViewState) {
        guard next != state else { return }
        state = next
    }
}

struct DesktopLyricsView: View {
    @ObservedObject var model: DesktopLyricsWindowModel

    private var nextLineFontSize: CGFloat {
        round(model.state.fontSize * 0.72)
    }

    var body: some View {
        let state = model.state
        VStack(spacing: 6) {
            karaokeCurrentLine(state: state)

            Text(state.presentation.nextLine ?? "")
                .font(.system(size: nextLineFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(state.presentation.nextLine == nil ? 0 : 1)
        }
        .padding(.horizontal, DesktopLyricsWindowLayout.horizontalPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: DesktopLyricsWindowLayout.maxCardWidth)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .opacity(state.isMouseHovering ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: state.isMouseHovering)
    }

    @ViewBuilder
    private func karaokeCurrentLine(state: DesktopLyricsViewState) -> some View {
        let text = state.presentation.currentLine ?? ""
        let fontSize = state.fontSize

        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                if let lineState = state.presentation.lineState, lineState.currentLine.isEmpty == false {
                    karaokeHighlightOverlay(lineState: lineState, fontSize: fontSize, color: state.highlightColor)
                }
            }
    }

    @ViewBuilder
    private func karaokeHighlightOverlay(
        lineState: DesktopLyricsLineState,
        fontSize: CGFloat,
        color: Color
    ) -> some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: lineState.lineStartDate, by: 1.0 / 30.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(lineState.lineStartDate))
                let characterFraction = DesktopLyricsKaraokeMath.fraction(
                    inlineTags: lineState.inlineTags,
                    lineTimeOffset: elapsed,
                    lineDuration: lineState.lineDuration,
                    characterCount: lineState.currentLine.count
                )
                let pixelFraction = DesktopLyricsKaraokePixelMath.pixelFraction(
                    characterFraction: characterFraction,
                    text: lineState.currentLine,
                    fontSize: fontSize
                )

                Text(lineState.currentLine)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: geo.size.width * pixelFraction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
            }
        }
    }
}

@MainActor
enum DesktopLyricsKaraokePixelMath {
    private struct CacheKey: Hashable {
        let text: String
        let fontSize: CGFloat
    }

    private struct CachedLine {
        let line: CTLine
        let totalWidth: CGFloat
    }

    private static var cache: [CacheKey: CachedLine] = [:]
    private static let cacheLimit = 32

    static func pixelFraction(
        characterFraction: Double,
        text: String,
        fontSize: CGFloat
    ) -> Double {
        guard text.isEmpty == false, characterFraction > 0 else { return 0 }
        guard characterFraction < 1.0 else { return 1.0 }

        let cached = cachedLine(text: text, fontSize: fontSize)
        let line = cached.line
        let totalWidth = cached.totalWidth
        guard totalWidth > 0 else { return characterFraction }

        let charCount = text.count
        let exactCharPos = characterFraction * Double(charCount)
        let floorCharIndex = min(Int(exactCharPos), charCount)
        let ceilCharIndex = min(floorCharIndex + 1, charCount)
        let interp = exactCharPos - Double(floorCharIndex)

        let floorStringIndex = text.index(text.startIndex, offsetBy: floorCharIndex)
        let floorUTF16 = floorStringIndex.utf16Offset(in: text)
        let floorOffset = CTLineGetOffsetForStringIndex(line, floorUTF16, nil)

        if ceilCharIndex == floorCharIndex || interp < 0.001 {
            return min(1.0, max(0.0, Double(floorOffset) / Double(totalWidth)))
        }

        let ceilStringIndex = text.index(text.startIndex, offsetBy: ceilCharIndex)
        let ceilUTF16 = ceilStringIndex.utf16Offset(in: text)
        let ceilOffset = CTLineGetOffsetForStringIndex(line, ceilUTF16, nil)

        let pixelOffset = floorOffset + CGFloat(interp) * (ceilOffset - floorOffset)
        return min(1.0, max(0.0, Double(pixelOffset) / Double(totalWidth)))
    }

    private static func cachedLine(text: String, fontSize: CGFloat) -> CachedLine {
        let key = CacheKey(text: text, fontSize: fontSize)
        if let hit = cache[key] {
            return hit
        }

        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let font = baseFont.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: fontSize) } ?? baseFont
        let attrString = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attrString)
        let totalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let value = CachedLine(line: line, totalWidth: totalWidth)

        if cache.count >= cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = value
        return value
    }
}

@MainActor
final class DesktopLyricsWindow: NSPanel {
    private let model = DesktopLyricsWindowModel()
    private var hostingView: NSHostingView<DesktopLyricsView>!

    init() {
        super.init(
            contentRect: DesktopLyricsWindowLayout.frame(in: .zero),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .statusBar
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        sharingType = .none
        hostingView = NSHostingView(rootView: DesktopLyricsView(model: model))
        contentView = hostingView
        orderOut(nil)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func update(
        presentation: DesktopLyricsPresentation,
        visibleFrame: CGRect,
        isMouseHovering: Bool,
        highlightColor: Color,
        fontSize: CGFloat
    ) {
        let nextState = DesktopLyricsViewState(
            presentation: presentation,
            isMouseHovering: isMouseHovering,
            highlightColor: highlightColor,
            fontSize: fontSize
        )
        model.update(nextState)

        let intrinsicSize = hostingView.intrinsicContentSize
        let cardWidth = max(200, intrinsicSize.width)
        setFrame(
            DesktopLyricsWindowLayout.frame(in: visibleFrame, cardWidth: cardWidth, fontSize: fontSize),
            display: false
        )
    }
}
