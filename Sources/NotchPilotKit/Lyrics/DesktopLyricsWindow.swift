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

@MainActor
final class DesktopLyricsWindowModel: ObservableObject {
    @Published var presentation: DesktopLyricsPresentation = .hidden
    @Published var isMouseHovering: Bool = false
    @Published var highlightColor: Color = .green
    @Published var fontSize: CGFloat = 28
}

struct DesktopLyricsView: View {
    @ObservedObject var model: DesktopLyricsWindowModel

    private var nextLineFontSize: CGFloat {
        round(model.fontSize * 0.72)
    }

    var body: some View {
        VStack(spacing: 6) {
            karaokeCurrentLine

            Text(model.presentation.nextLine ?? "")
                .font(.system(size: nextLineFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(model.presentation.nextLine == nil ? 0 : 1)
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
        .opacity(model.isMouseHovering ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: model.isMouseHovering)
    }

    @ViewBuilder
    private var karaokeCurrentLine: some View {
        let text = model.presentation.currentLine ?? ""
        let characterFraction = model.presentation.karaokeFraction

        Text(text)
            .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                GeometryReader { geo in
                    let pixelFraction = Self.pixelFraction(
                        characterFraction: characterFraction,
                        text: text,
                        fontSize: model.fontSize
                    )
                    Text(text)
                        .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.highlightColor)
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

    private static func pixelFraction(
        characterFraction: Double,
        text: String,
        fontSize: CGFloat
    ) -> Double {
        guard !text.isEmpty, characterFraction > 0 else { return 0 }
        guard characterFraction < 1.0 else { return 1.0 }

        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let font = baseFont.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: fontSize) } ?? baseFont
        let attrString = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attrString)
        let totalWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
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
            return min(1.0, max(0.0, Double(floorOffset) / totalWidth))
        }

        let ceilStringIndex = text.index(text.startIndex, offsetBy: ceilCharIndex)
        let ceilUTF16 = ceilStringIndex.utf16Offset(in: text)
        let ceilOffset = CTLineGetOffsetForStringIndex(line, ceilUTF16, nil)

        let pixelOffset = floorOffset + CGFloat(interp) * (ceilOffset - floorOffset)
        return min(1.0, max(0.0, Double(pixelOffset) / totalWidth))
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
        model.presentation = presentation
        model.isMouseHovering = isMouseHovering
        model.highlightColor = highlightColor
        model.fontSize = fontSize

        let intrinsicSize = hostingView.intrinsicContentSize
        let cardWidth = max(200, intrinsicSize.width)
        setFrame(
            DesktopLyricsWindowLayout.frame(in: visibleFrame, cardWidth: cardWidth, fontSize: fontSize),
            display: false
        )
    }
}
