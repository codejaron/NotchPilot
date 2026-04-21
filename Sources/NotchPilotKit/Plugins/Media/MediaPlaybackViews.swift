import AppKit
import SwiftUI

enum MediaPlaybackExpandedLayout {
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 10
    static let contentSpacing: CGFloat = 16
    static let metadataSpacing: CGFloat = 3
    static let sectionSpacing: CGFloat = 8

    static let artworkSize: CGFloat = 112
    static let artworkCornerRadius: CGFloat = 22

    static let titleFontSize: CGFloat = 18
    static let artistFontSize: CGFloat = 13
    static let albumFontSize: CGFloat = 11
    static let sourceBadgeFontSize: CGFloat = 11
    static let sourceBadgeHorizontalPadding: CGFloat = 10
    static let sourceBadgeVerticalPadding: CGFloat = 6
    static let sourceBadgeInset: CGFloat = 8

    static let timeFontSize: CGFloat = 11
    static let progressSectionHeight: CGFloat = 34

    static let previousNextButtonSize: CGFloat = 30
    static let previousNextIconSize: CGFloat = 18
    static let playPauseButtonSize: CGFloat = 40
    static let playPauseIconSize: CGFloat = 22
    static let controlSpacing: CGFloat = 18

    static let titleLineHeight: CGFloat = 21
    static let artistLineHeight: CGFloat = 15
    static let albumLineHeight: CGFloat = 12

    static func estimatedContentHeight(titleLineCount: Int = 2) -> CGFloat {
        let metadataHeight =
            CGFloat(titleLineCount) * titleLineHeight +
            metadataSpacing +
            artistLineHeight +
            metadataSpacing +
            albumLineHeight
        let detailColumnHeight =
            metadataHeight +
            sectionSpacing +
            progressSectionHeight +
            sectionSpacing +
            playPauseButtonSize

        return (verticalPadding * 2) + max(artworkSize, detailColumnHeight)
    }
}

enum MediaPlaybackProgressChrome {
    static let hitHeight: CGFloat = 14
    static let trackHeight: CGFloat = 5
    static let restingThumbDiameter: CGFloat = 10
    static let activeThumbDiameter: CGFloat = 12

    static let inactiveTrackOpacity = 0.18
    static let filledTrackOpacity = 0.96

    static func progressFraction(value: Double, in range: ClosedRange<Double>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else {
            return 0
        }

        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clampedValue - range.lowerBound) / span)
    }

    static func inactiveTrackLuminance(onBackgroundLuminance backgroundLuminance: Double) -> Double {
        blendedWhiteLuminance(opacity: inactiveTrackOpacity, backgroundLuminance: backgroundLuminance)
    }

    static func filledTrackLuminance(onBackgroundLuminance backgroundLuminance: Double) -> Double {
        blendedWhiteLuminance(opacity: filledTrackOpacity, backgroundLuminance: backgroundLuminance)
    }

    private static func blendedWhiteLuminance(opacity: Double, backgroundLuminance: Double) -> Double {
        min(1, max(0, opacity)) + min(1, max(0, backgroundLuminance)) * (1 - min(1, max(0, opacity)))
    }
}

enum MediaPlaybackCompactPreviewLayout {
    static let edgePadding: CGFloat = 12
    static let cameraEdgeSpacing: CGFloat = 6
    static let artworkSize: CGFloat = 24
    static let artworkCornerRadius: CGFloat = 5
    static let levelIndicatorWidth: CGFloat = 16
    static let levelIndicatorHeight: CGFloat = 12
    static let levelGradientWidth: CGFloat = 50
    static let levelBarWidth: CGFloat = 2
    static let levelBarSpacing: CGFloat = 2
    static let levelAnimationInterval: TimeInterval = 0.3

    static var artworkAccessoryWidth: CGFloat {
        edgePadding + artworkSize + cameraEdgeSpacing
    }

    static var levelAccessoryWidth: CGFloat {
        cameraEdgeSpacing + levelIndicatorWidth + edgePadding
    }

    static func preferredWidth(forCompactWidth compactWidth: CGFloat) -> CGFloat {
        compactWidth + artworkAccessoryWidth + levelAccessoryWidth
    }
}

enum MediaPlaybackArtworkPalette {
    static func spectrumColor(for snapshot: MediaPlaybackSnapshot) -> Color {
        guard let color = averageSRGBColor(from: snapshot.artworkData) else {
            return NotchPilotTheme.mediaPlayback
        }

        return Color(nsColor: visibleSpectrumColor(from: color))
    }

    static func averageSRGBColor(from artworkData: Data?) -> NSColor? {
        guard let artworkData else {
            return nil
        }

        let bitmapRep: NSBitmapImageRep?
        if let rep = NSBitmapImageRep(data: artworkData) {
            bitmapRep = rep
        } else if let image = NSImage(data: artworkData),
                  let tiffData = image.tiffRepresentation {
            bitmapRep = NSBitmapImageRep(data: tiffData)
        } else {
            bitmapRep = nil
        }

        guard let bitmapRep,
              bitmapRep.pixelsWide > 0,
              bitmapRep.pixelsHigh > 0 else {
            return nil
        }

        let sampleLimit = 16
        let stepX = max(1, bitmapRep.pixelsWide / sampleLimit)
        let stepY = max(1, bitmapRep.pixelsHigh / sampleLimit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var count: CGFloat = 0

        for y in stride(from: 0, to: bitmapRep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: bitmapRep.pixelsWide, by: stepX) {
                guard let color = bitmapRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.05 else {
                    continue
                }

                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                count += 1
            }
        }

        guard count > 0 else {
            return nil
        }

        return NSColor(srgbRed: red / count, green: green / count, blue: blue / count, alpha: 1)
    }

    private static func visibleSpectrumColor(from color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            return color
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            calibratedHue: hue,
            saturation: max(saturation, 0.35),
            brightness: max(brightness, 0.55),
            alpha: 1
        )
    }
}

private struct MediaPlaybackProgressScrubber: View {
    @ObservedObject private var store = SettingsStore.shared

    let value: Double
    let range: ClosedRange<Double>
    let isSeekable: Bool
    let onValueChanged: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = MediaPlaybackProgressChrome.progressFraction(value: value, in: range)
            let thumbDiameter = isDragging
                ? MediaPlaybackProgressChrome.activeThumbDiameter
                : MediaPlaybackProgressChrome.restingThumbDiameter
            let thumbOffset = min(
                max(0, width * fraction - thumbDiameter / 2),
                max(0, width - thumbDiameter)
            )
            let filledWidth = fraction > 0
                ? max(MediaPlaybackProgressChrome.trackHeight, width * fraction)
                : 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(MediaPlaybackProgressChrome.inactiveTrackOpacity))
                    .frame(height: MediaPlaybackProgressChrome.trackHeight)

                Capsule(style: .continuous)
                    .fill(.white.opacity(MediaPlaybackProgressChrome.filledTrackOpacity))
                    .frame(width: filledWidth, height: MediaPlaybackProgressChrome.trackHeight)

                Circle()
                    .fill(.white.opacity(isSeekable ? 1 : 0.72))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: thumbOffset)
            }
            .frame(width: width, height: MediaPlaybackProgressChrome.hitHeight, alignment: .center)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: MediaPlaybackProgressChrome.hitHeight)
        .accessibilityLabel(AppStrings.text(.playbackProgress, language: store.interfaceLanguage))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard isSeekable else {
                    return
                }

                if isDragging == false {
                    isDragging = true
                    onEditingChanged(true)
                }

                onValueChanged(value(at: gesture.location.x, width: width))
            }
            .onEnded { gesture in
                let wasDragging = isDragging
                isDragging = false

                guard isSeekable else {
                    return
                }

                onValueChanged(value(at: gesture.location.x, width: width))
                if wasDragging {
                    onEditingChanged(false)
                }
            }
    }

    private func value(at xPosition: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else {
            return range.lowerBound
        }

        let fraction = min(max(xPosition / width, 0), 1)
        return range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
    }
}

private struct MediaPlaybackSneakArtworkView: View {
    let snapshot: MediaPlaybackSnapshot

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: MediaPlaybackCompactPreviewLayout.artworkCornerRadius,
                style: .continuous
            )
            .fill(NotchPilotTheme.mediaPlayback.opacity(0.24))

            if let artworkData = snapshot.artworkData,
               let image = NSImage(data: artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: snapshot.source.systemImageName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(
            width: MediaPlaybackCompactPreviewLayout.artworkSize,
            height: MediaPlaybackCompactPreviewLayout.artworkSize
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: MediaPlaybackCompactPreviewLayout.artworkCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MediaPlaybackCompactPreviewLayout.artworkCornerRadius,
                style: .continuous
            )
            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}

private struct MediaPlaybackLevelIndicatorView: View {
    let isPlaying: Bool
    let accentColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: MediaPlaybackCompactPreviewLayout.levelAnimationInterval)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / MediaPlaybackCompactPreviewLayout.levelAnimationInterval)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.72),
                            accentColor.opacity(0.98),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(
                    width: MediaPlaybackCompactPreviewLayout.levelGradientWidth,
                    height: MediaPlaybackCompactPreviewLayout.levelIndicatorHeight
                )
                .mask {
                    HStack(alignment: .center, spacing: MediaPlaybackCompactPreviewLayout.levelBarSpacing) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule(style: .continuous)
                                .frame(
                                    width: MediaPlaybackCompactPreviewLayout.levelBarWidth,
                                    height: barHeight(index: index, tick: tick)
                                )
                        }
                    }
                    .frame(
                        width: MediaPlaybackCompactPreviewLayout.levelIndicatorWidth,
                        height: MediaPlaybackCompactPreviewLayout.levelIndicatorHeight,
                        alignment: .center
                    )
                }
                .animation(
                    .easeInOut(duration: MediaPlaybackCompactPreviewLayout.levelAnimationInterval),
                    value: tick
                )
        }
        .frame(
            width: MediaPlaybackCompactPreviewLayout.levelIndicatorWidth,
            height: MediaPlaybackCompactPreviewLayout.levelIndicatorHeight,
            alignment: .center
        )
        .accessibilityHidden(true)
    }

    private func barHeight(index: Int, tick: Int) -> CGFloat {
        guard isPlaying else {
            let restingHeights: [CGFloat] = [5, 9, 7, 4]
            return restingHeights[index]
        }

        let seed = sin(Double((tick + 1) * (index + 3)) * 12.9898 + Double(index) * 78.233) * 43758.5453
        let normalized = seed - floor(seed)
        let minimumScale: CGFloat = 0.35
        let scale = minimumScale + CGFloat(normalized) * (1 - minimumScale)
        return MediaPlaybackCompactPreviewLayout.levelIndicatorHeight * scale
    }
}

struct MediaPlaybackCompactPreviewView: View {
    let snapshot: MediaPlaybackSnapshot
    let totalWidth: CGFloat
    let cameraClearanceWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(width: MediaPlaybackCompactPreviewLayout.edgePadding)
                MediaPlaybackSneakArtworkView(snapshot: snapshot)
                Spacer(minLength: 0)
                    .frame(width: MediaPlaybackCompactPreviewLayout.cameraEdgeSpacing)
            }
            .frame(width: MediaPlaybackCompactPreviewLayout.artworkAccessoryWidth)

            Spacer(minLength: 0)
                .frame(width: cameraClearanceWidth)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(width: MediaPlaybackCompactPreviewLayout.cameraEdgeSpacing)
                MediaPlaybackLevelIndicatorView(
                    isPlaying: snapshot.isPlaying,
                    accentColor: MediaPlaybackArtworkPalette.spectrumColor(for: snapshot)
                )
                Spacer(minLength: 0)
                    .frame(width: MediaPlaybackCompactPreviewLayout.edgePadding)
            }
            .frame(width: MediaPlaybackCompactPreviewLayout.levelAccessoryWidth)
        }
        .frame(width: totalWidth, height: notchHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(snapshot.title.isEmpty ? snapshot.source.displayName : snapshot.title), \(snapshot.artist.isEmpty ? snapshot.source.displayName : snapshot.artist)")
        )
    }
}

struct MediaPlaybackExpandedView: View {
    private struct PendingSeek {
        let time: Double
        let issuedAt: Date
    }

    let state: MediaPlaybackState
    let accentColor: Color
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void

    @ObservedObject private var store = SettingsStore.shared
    @State private var editingTime: Double?
    @State private var pendingSeek: PendingSeek?

    var body: some View {
        switch state {
        case let .active(snapshot):
            HStack(alignment: .center, spacing: MediaPlaybackExpandedLayout.contentSpacing) {
                artworkCard(snapshot)

                VStack(alignment: .leading, spacing: MediaPlaybackExpandedLayout.sectionSpacing) {
                    metadataSection(snapshot)
                    progressSection(snapshot)
                    controlsRow(snapshot)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, MediaPlaybackExpandedLayout.horizontalPadding)
            .padding(.vertical, MediaPlaybackExpandedLayout.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onChange(of: snapshot.currentTime) { _, newValue in
                guard editingTime == nil else {
                    return
                }
                if let pendingSeek,
                   abs(newValue - pendingSeek.time) <= 1.0 || snapshot.lastUpdated >= pendingSeek.issuedAt {
                    self.pendingSeek = nil
                }
            }
            .onAppear {
                editingTime = nil
            }
            .onChange(of: snapshot.lastUpdated) { _, newValue in
                guard let pendingSeek else {
                    return
                }

                if newValue >= pendingSeek.issuedAt {
                    self.pendingSeek = nil
                }
            }

        case .idle, .unavailable:
            Text(AppStrings.text(.noActiveMediaPlayback, language: store.interfaceLanguage))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, MediaPlaybackExpandedLayout.horizontalPadding)
                .padding(.vertical, MediaPlaybackExpandedLayout.verticalPadding)
        }
    }

    @ViewBuilder
    private func artworkCard(_ snapshot: MediaPlaybackSnapshot) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(
                cornerRadius: MediaPlaybackExpandedLayout.artworkCornerRadius,
                style: .continuous
            )
                .fill(accentColor.opacity(0.22))
                .frame(
                    width: MediaPlaybackExpandedLayout.artworkSize,
                    height: MediaPlaybackExpandedLayout.artworkSize
                )
                .overlay {
                    if let artworkData = snapshot.artworkData,
                       let image = NSImage(data: artworkData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: MediaPlaybackExpandedLayout.artworkSize,
                                height: MediaPlaybackExpandedLayout.artworkSize
                            )
                            .clipped()
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: MediaPlaybackExpandedLayout.artworkCornerRadius,
                                    style: .continuous
                                )
                            )
                    } else {
                        Image(systemName: snapshot.source.systemImageName)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }

            HStack(spacing: 6) {
                Image(systemName: snapshot.source.systemImageName)
                    .font(.system(size: MediaPlaybackExpandedLayout.sourceBadgeFontSize, weight: .bold))

                Text(snapshot.source.displayName)
                    .font(.system(size: MediaPlaybackExpandedLayout.sourceBadgeFontSize, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MediaPlaybackExpandedLayout.sourceBadgeHorizontalPadding)
            .padding(.vertical, MediaPlaybackExpandedLayout.sourceBadgeVerticalPadding)
            .background(.black.opacity(0.72), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .padding(MediaPlaybackExpandedLayout.sourceBadgeInset)
        }
    }

    private func metadataSection(_ snapshot: MediaPlaybackSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MediaPlaybackExpandedLayout.metadataSpacing) {
            Text(snapshot.title.isEmpty ? AppStrings.text(.unknownTrack, language: store.interfaceLanguage) : snapshot.title)
                .font(.system(size: MediaPlaybackExpandedLayout.titleFontSize, weight: .bold))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .lineLimit(2)

            Text(snapshot.artist.isEmpty ? snapshot.source.displayName : snapshot.artist)
                .font(.system(size: MediaPlaybackExpandedLayout.artistFontSize, weight: .semibold))
                .foregroundStyle(accentColor)
                .lineLimit(1)

            Text(snapshot.album.isEmpty ? snapshot.source.displayName : snapshot.album)
                .font(.system(size: MediaPlaybackExpandedLayout.albumFontSize, weight: .medium))
                .foregroundStyle(NotchPilotTheme.islandTextMuted)
                .lineLimit(1)
        }
    }

    private func progressSection(_ snapshot: MediaPlaybackSnapshot) -> some View {
        let displayedCurrentTime = resolvedCurrentTime(for: snapshot)
        let duration = snapshot.duration ?? 0
        let upperBound = max(snapshot.duration ?? max(displayedCurrentTime, 1), 1)

        return VStack(alignment: .leading, spacing: 6) {
            MediaPlaybackProgressScrubber(
                value: duration > 0 ? editingTime ?? displayedCurrentTime : 0,
                range: 0...upperBound,
                isSeekable: duration > 0,
                onValueChanged: { editingTime = $0 },
                onEditingChanged: { isEditing in
                    if isEditing {
                        editingTime = editingTime ?? displayedCurrentTime
                    } else {
                        let resolvedTime = editingTime ?? resolvedCurrentTime(for: snapshot)
                        pendingSeek = PendingSeek(time: resolvedTime, issuedAt: Date())
                        onSeek(resolvedTime)
                        editingTime = nil
                    }
                }
            )

            HStack {
                Text(timeString(displayedCurrentTime))
                Spacer(minLength: 0)
                Text(timeString(snapshot.duration ?? 0))
            }
            .font(.system(size: MediaPlaybackExpandedLayout.timeFontSize, weight: .semibold))
            .foregroundStyle(accentColor)
            .monospacedDigit()
        }
        .frame(height: MediaPlaybackExpandedLayout.progressSectionHeight, alignment: .top)
    }

    private func controlsRow(_ snapshot: MediaPlaybackSnapshot) -> some View {
        HStack(spacing: MediaPlaybackExpandedLayout.controlSpacing) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: MediaPlaybackExpandedLayout.previousNextIconSize, weight: .bold))
                    .frame(
                        width: MediaPlaybackExpandedLayout.previousNextButtonSize,
                        height: MediaPlaybackExpandedLayout.previousNextButtonSize
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)

            Button(action: onPlayPause) {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: MediaPlaybackExpandedLayout.playPauseIconSize, weight: .bold))
                    .frame(
                        width: MediaPlaybackExpandedLayout.playPauseButtonSize,
                        height: MediaPlaybackExpandedLayout.playPauseButtonSize
                    )
                    .background(
                        Circle()
                            .fill(.white.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)

            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: MediaPlaybackExpandedLayout.previousNextIconSize, weight: .bold))
                    .frame(
                        width: MediaPlaybackExpandedLayout.previousNextButtonSize,
                        height: MediaPlaybackExpandedLayout.previousNextButtonSize
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: MediaPlaybackExpandedLayout.playPauseButtonSize, alignment: .center)
    }

    private func timeString(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func resolvedCurrentTime(for snapshot: MediaPlaybackSnapshot) -> Double {
        if let editingTime {
            return editingTime
        }

        if let pendingSeek {
            let elapsedSinceSeek = snapshot.isPlaying ? Date().timeIntervalSince(pendingSeek.issuedAt) * snapshot.playbackRate : 0
            let projectedTime = pendingSeek.time + elapsedSinceSeek
            let upperBound = snapshot.duration ?? projectedTime
            return min(max(0, projectedTime), max(upperBound, 0))
        }

        return snapshot.estimatedCurrentTime()
    }
}
