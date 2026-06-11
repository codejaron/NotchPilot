import Combine
import Foundation

@MainActor
final class DesktopLyricsController: ObservableObject {
    @Published private(set) var presentation: DesktopLyricsPresentation = .hidden

    private static let pendingRefreshTolerance: TimeInterval = 0.02

    private let settingsStore: SettingsStore
    private let provider: LyricsProviding
    private let cache: LyricsCaching
    private let ignoredTrackStore: LyricsTrackIgnoring
    private let offsetStore: LyricsOffsetStoring
    private let playbackTimeProvider: (MediaPlaybackSnapshot) -> TimeInterval?

    private var currentPlaybackState: MediaPlaybackState = .idle
    private(set) var currentTrackKey: LyricsTrackKey?
    private var currentLyrics: TimedLyrics?
    private(set) var currentOffsetMilliseconds: Int = 0
    private var loadTask: Task<Void, Never>?
    private var pendingPresentationRefreshTask: Task<Void, Never>?
    private var activeLyricsPreview: LyricsPreview?
    private var playbackTimeAnchor: PlaybackTimeAnchor?
    private var settingsCancellables: Set<AnyCancellable> = []

    private struct LyricsPreview {
        let trackKey: LyricsTrackKey
        var originalLyrics: TimedLyrics?
    }

    private struct PlaybackTimeAnchor {
        let trackKey: LyricsTrackKey
        let source: MediaPlaybackSource
        let time: TimeInterval
        let date: Date
        let playbackRate: Double
        let duration: TimeInterval?

        func matches(trackKey: LyricsTrackKey, source: MediaPlaybackSource, at date: Date) -> Bool {
            let elapsed = date.timeIntervalSince(self.date)
            return self.trackKey == trackKey &&
                self.source == source &&
                elapsed >= 0 &&
                elapsed <= 12
        }

        func projectedTime(at date: Date) -> TimeInterval {
            let elapsed = max(0, date.timeIntervalSince(self.date))
            let projected = time + (elapsed * max(0, playbackRate))
            guard let duration else {
                return max(0, projected)
            }
            return min(max(0, projected), max(0, duration))
        }
    }

    init(
        settingsStore: SettingsStore = .shared,
        provider: LyricsProviding,
        cache: LyricsCaching,
        ignoredTrackStore: LyricsTrackIgnoring,
        offsetStore: LyricsOffsetStoring = LyricsOffsetStore(),
        playbackTimeProvider: @escaping (MediaPlaybackSnapshot) -> TimeInterval? = { _ in nil }
    ) {
        self.settingsStore = settingsStore
        self.provider = provider
        self.cache = cache
        self.ignoredTrackStore = ignoredTrackStore
        self.offsetStore = offsetStore
        self.playbackTimeProvider = playbackTimeProvider

        settingsStore.$desktopLyricsEnabled
            .combineLatest(settingsStore.$mediaPlaybackEnabled)
            .sink { [weak self] _, _ in
                self?.refreshForCurrentState()
            }
            .store(in: &settingsCancellables)
    }

    deinit {
        loadTask?.cancel()
        pendingPresentationRefreshTask?.cancel()
    }

    func handlePlaybackState(_ state: MediaPlaybackState) {
        currentPlaybackState = state
        refreshForCurrentState()
    }

    func refreshPresentation(at date: Date = Date()) {
        guard settingsStore.mediaPlaybackEnabled,
              settingsStore.desktopLyricsEnabled,
              case let .active(snapshot) = currentPlaybackState,
              snapshot.isPlaying,
              DesktopLyricsPlaybackFilter.isEligible(snapshot) else {
            cancelPendingPresentationRefresh()
            assignPresentation(.hidden)
            return
        }

        let trackKey = LyricsTrackKey(snapshot: snapshot)
        let resolvedSnapshot = resolvePlaybackSnapshot(snapshot, trackKey: trackKey, at: date)

        let nextPresentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: .active(resolvedSnapshot),
            lyrics: currentLyrics,
            offsetMilliseconds: currentOffsetMilliseconds,
            at: date
        )
        assignPresentation(nextPresentation)
        schedulePendingPresentationRefresh(
            for: nextPresentation,
            snapshot: resolvedSnapshot,
            lyrics: currentLyrics,
            offsetMilliseconds: currentOffsetMilliseconds,
            at: date
        )
    }

    private func resolvePlaybackSnapshot(
        _ snapshot: MediaPlaybackSnapshot,
        trackKey: LyricsTrackKey,
        at date: Date
    ) -> MediaPlaybackSnapshot {
        let projectedTime = playbackTimeAnchor
            .flatMap { anchor -> TimeInterval? in
                guard anchor.matches(trackKey: trackKey, source: snapshot.source, at: date) else {
                    return nil
                }
                return anchor.projectedTime(at: date)
            }

        if let directPlaybackTime = playbackTimeProvider(snapshot) {
            if let projectedTime,
               directPlaybackTime <= 0.25,
               projectedTime > 2 {
                return snapshot.replacingCurrentTime(projectedTime, at: date)
            }

            playbackTimeAnchor = PlaybackTimeAnchor(
                trackKey: trackKey,
                source: snapshot.source,
                time: directPlaybackTime,
                date: date,
                playbackRate: snapshot.playbackRate,
                duration: snapshot.duration
            )
            return snapshot.replacingCurrentTime(directPlaybackTime, at: date)
        }

        if let projectedTime {
            return snapshot.replacingCurrentTime(projectedTime, at: date)
        }

        return snapshot
    }

    private func assignPresentation(_ next: DesktopLyricsPresentation) {
        guard next != presentation else { return }
        presentation = next
    }

    private func schedulePendingPresentationRefresh(
        for presentation: DesktopLyricsPresentation,
        snapshot: MediaPlaybackSnapshot,
        lyrics: TimedLyrics?,
        offsetMilliseconds: Int,
        at date: Date
    ) {
        pendingPresentationRefreshTask?.cancel()
        pendingPresentationRefreshTask = nil

        guard presentation.isVisible == false,
              let refreshDate = nextLineStartDate(
                snapshot: snapshot,
                lyrics: lyrics,
                offsetMilliseconds: offsetMilliseconds,
                at: date
              ) else {
            return
        }

        let fireDate = refreshDate.addingTimeInterval(Self.pendingRefreshTolerance)
        let delay = max(0, fireDate.timeIntervalSince(Date()))
        pendingPresentationRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard Task.isCancelled == false else {
                return
            }
            self?.pendingPresentationRefreshTask = nil
            self?.refreshPresentation()
        }
    }

    private func nextLineStartDate(
        snapshot: MediaPlaybackSnapshot,
        lyrics: TimedLyrics?,
        offsetMilliseconds: Int,
        at date: Date
    ) -> Date? {
        guard let lyrics, snapshot.isPlaying, snapshot.playbackRate > 0 else {
            return nil
        }

        let totalOffsetMilliseconds = offsetMilliseconds + lyrics.sourceOffsetMilliseconds
        let offset = TimeInterval(totalOffsetMilliseconds) / 1000.0
        let adjustedTime = snapshot.estimatedCurrentTime(at: date) + offset

        guard let nextLine = lyrics.lines.first(where: { $0.timestamp > adjustedTime }) else {
            return nil
        }

        let secondsUntilNextLine = (nextLine.timestamp - adjustedTime) / snapshot.playbackRate
        guard secondsUntilNextLine.isFinite, secondsUntilNextLine >= 0 else {
            return nil
        }

        return date.addingTimeInterval(secondsUntilNextLine)
    }

    private func cancelPendingPresentationRefresh() {
        pendingPresentationRefreshTask?.cancel()
        pendingPresentationRefreshTask = nil
    }

    var canAdjustLyricsOffset: Bool {
        currentTrackKey != nil && currentLyrics != nil
    }

    func setLyricsOffset(_ milliseconds: Int) {
        guard let currentTrackKey else { return }
        currentOffsetMilliseconds = milliseconds
        offsetStore.setOffset(milliseconds, for: currentTrackKey)
        refreshPresentation()
    }

    var currentLyricsFileURL: URL? {
        guard let currentTrackKey else {
            return nil
        }

        return cache.fileURL(for: currentTrackKey)
    }

    var currentSearchSnapshot: MediaPlaybackSnapshot? {
        guard case let .active(snapshot) = currentPlaybackState,
              snapshot.isPlaying,
              DesktopLyricsPlaybackFilter.isEligible(snapshot) else {
            return nil
        }

        return snapshot
    }

    var canIgnoreCurrentTrackLyrics: Bool {
        currentTrackKey != nil
    }

    var canSearchCurrentTrackLyrics: Bool {
        currentSearchSnapshot != nil
    }

    func ignoreCurrentTrackLyrics() {
        guard let currentTrackKey else {
            return
        }

        loadTask?.cancel()
        loadTask = nil
        activeLyricsPreview = nil
        cancelPendingPresentationRefresh()
        ignoredTrackStore.insert(currentTrackKey)
        try? cache.removeLyrics(for: currentTrackKey)
        currentLyrics = nil
        assignPresentation(.hidden)
    }

    func applyLyricsOverride(_ lyrics: TimedLyrics, for snapshot: MediaPlaybackSnapshot) {
        let trackKey = LyricsTrackKey(snapshot: snapshot)
        activeLyricsPreview = nil
        ignoredTrackStore.remove(trackKey)
        try? cache.saveLyrics(lyrics, for: trackKey)

        let currentSearchTrackKey = currentSearchSnapshot.map { LyricsTrackKey(snapshot: $0) }
        guard currentTrackKey == trackKey || currentSearchTrackKey == trackKey else {
            return
        }

        currentTrackKey = trackKey
        currentLyrics = lyrics
        refreshPresentation()
    }

    func previewLyricsOverride(_ lyrics: TimedLyrics, for snapshot: MediaPlaybackSnapshot) {
        let trackKey = LyricsTrackKey(snapshot: snapshot)
        let currentSearchTrackKey = currentSearchSnapshot.map { LyricsTrackKey(snapshot: $0) }
        guard currentTrackKey == trackKey || currentSearchTrackKey == trackKey else {
            return
        }

        if activeLyricsPreview?.trackKey != trackKey {
            activeLyricsPreview = LyricsPreview(trackKey: trackKey, originalLyrics: currentLyrics)
        }

        currentTrackKey = trackKey
        currentLyrics = lyrics
        refreshPresentation()
    }

    func cancelLyricsOverridePreview(for snapshot: MediaPlaybackSnapshot) {
        let trackKey = LyricsTrackKey(snapshot: snapshot)
        guard let preview = activeLyricsPreview, preview.trackKey == trackKey else {
            return
        }

        currentLyrics = preview.originalLyrics
        activeLyricsPreview = nil
        refreshPresentation()
    }

    private func refreshForCurrentState() {
        guard settingsStore.mediaPlaybackEnabled, settingsStore.desktopLyricsEnabled else {
            resetPresentation(clearLyrics: false)
            return
        }

        guard case let .active(snapshot) = currentPlaybackState else {
            resetPresentation(clearLyrics: true)
            return
        }

        guard snapshot.isPlaying else {
            resetPresentation(clearLyrics: false)
            return
        }

        guard DesktopLyricsPlaybackFilter.isEligible(snapshot) else {
            resetPresentation(clearLyrics: true)
            return
        }

        let trackKey = LyricsTrackKey(snapshot: snapshot)
        guard ignoredTrackStore.contains(trackKey) == false else {
            activeLyricsPreview = nil
            currentTrackKey = trackKey
            currentLyrics = nil
            assignPresentation(.hidden)
            loadTask?.cancel()
            loadTask = nil
            return
        }

        if currentTrackKey != trackKey {
            activeLyricsPreview = nil
            currentTrackKey = trackKey
            currentLyrics = nil
            playbackTimeAnchor = nil
            currentOffsetMilliseconds = offsetStore.offset(for: trackKey)
            cancelPendingPresentationRefresh()
            assignPresentation(.hidden)
            loadTask?.cancel()
            loadTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                var didReceiveLyrics = false
                for await lyrics in provider.lyricUpdates(for: snapshot) {
                    guard Task.isCancelled == false else {
                        break
                    }
                    didReceiveLyrics = true
                    self.completeLyricsLoad(lyrics, for: trackKey)
                }

                if didReceiveLyrics == false, Task.isCancelled == false {
                    self.completeLyricsLoad(nil, for: trackKey)
                }
            }
            return
        }

        refreshPresentation()
    }

    func completeLyricsLoad(_ lyrics: TimedLyrics?, for trackKey: LyricsTrackKey) {
        guard currentTrackKey == trackKey else {
            return
        }

        cancelPendingPresentationRefresh()
        if activeLyricsPreview?.trackKey == trackKey {
            activeLyricsPreview?.originalLyrics = lyrics
            return
        }

        currentLyrics = lyrics
        refreshPresentation()
    }

    private func resetPresentation(clearLyrics: Bool) {
        loadTask?.cancel()
        loadTask = nil
        cancelPendingPresentationRefresh()
        if clearLyrics {
            activeLyricsPreview = nil
            currentLyrics = nil
            currentTrackKey = nil
        }
        playbackTimeAnchor = nil
        assignPresentation(.hidden)
    }
}
