import AppKit
import Combine
import SwiftUI

enum DesktopLyricsWindowLayout {
    static let cardSize = CGSize(width: 420, height: 88)
    static let bottomInset: CGFloat = 28

    static func frame(for size: CGSize = cardSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.minY + bottomInset,
            width: size.width,
            height: size.height
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
}

struct DesktopLyricsView: View {
    @ObservedObject var model: DesktopLyricsWindowModel

    var body: some View {
        VStack(spacing: 6) {
            Text(model.presentation.currentLine ?? "")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Text(model.presentation.nextLine ?? "")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .opacity(model.presentation.nextLine == nil ? 0 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(
            width: DesktopLyricsWindowLayout.cardSize.width,
            height: DesktopLyricsWindowLayout.cardSize.height
        )
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .animation(.easeInOut(duration: 0.18), value: model.presentation)
    }
}

@MainActor
final class DesktopLyricsWindow: NSPanel {
    private let model = DesktopLyricsWindowModel()

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
        contentView = NSHostingView(rootView: DesktopLyricsView(model: model))
        orderOut(nil)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func update(presentation: DesktopLyricsPresentation, visibleFrame: CGRect) {
        model.presentation = presentation
        setFrame(DesktopLyricsWindowLayout.frame(in: visibleFrame), display: false)
    }
}
