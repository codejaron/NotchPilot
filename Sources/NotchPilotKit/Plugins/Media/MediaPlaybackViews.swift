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

struct MediaPlaybackCompactPreviewView: View {
    let snapshot: MediaPlaybackSnapshot
    let totalWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.source.systemImageName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.artist.isEmpty ? snapshot.source.displayName : snapshot.artist)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                    .lineLimit(1)

                Text(snapshot.title.isEmpty ? snapshot.source.displayName : snapshot.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: totalWidth, height: notchHeight, alignment: .center)
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
            Text("No active media playback.")
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
            Text(snapshot.title.isEmpty ? "Unknown Track" : snapshot.title)
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

        return VStack(alignment: .leading, spacing: 8) {
            Slider(
                value: Binding(
                    get: { editingTime ?? resolvedCurrentTime(for: snapshot) },
                    set: { editingTime = $0 }
                ),
                in: 0...max(snapshot.duration ?? max(displayedCurrentTime, 1), 1),
                onEditingChanged: { isEditing in
                    if isEditing == false {
                        let resolvedTime = editingTime ?? resolvedCurrentTime(for: snapshot)
                        pendingSeek = PendingSeek(time: resolvedTime, issuedAt: Date())
                        onSeek(resolvedTime)
                        editingTime = nil
                    }
                }
            )
            .tint(accentColor)
            .controlSize(.small)
            .disabled((snapshot.duration ?? 0) <= 0)

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
