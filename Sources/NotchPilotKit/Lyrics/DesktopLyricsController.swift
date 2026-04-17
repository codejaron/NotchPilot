import Combine
import Foundation

@MainActor
final class DesktopLyricsController: ObservableObject {
    @Published private(set) var presentation: DesktopLyricsPresentation = .hidden

    private let settingsStore: SettingsStore
    private let provider: LyricsProviding
    private let cache: LyricsCaching
    private let ignoredTrackStore: LyricsTrackIgnoring
    private let offsetStore: LyricsOffsetStoring

    private var currentPlaybackState: MediaPlaybackState = .idle
    private(set) var currentTrackKey: LyricsTrackKey?
    private var currentLyrics: TimedLyrics?
    private(set) var currentOffsetMilliseconds: Int = 0
    private var loadTask: Task<Void, Never>?
    private var settingsCancellables: Set<AnyCancellable> = []

    init(
        settingsStore: SettingsStore = .shared,
        provider: LyricsProviding,
        cache: LyricsCaching,
        ignoredTrackStore: LyricsTrackIgnoring,
        offsetStore: LyricsOffsetStoring = LyricsOffsetStore()
    ) {
        self.settingsStore = settingsStore
        self.provider = provider
        self.cache = cache
        self.ignoredTrackStore = ignoredTrackStore
        self.offsetStore = offsetStore

        settingsStore.$desktopLyricsEnabled
            .combineLatest(settingsStore.$mediaPlaybackEnabled)
            .sink { [weak self] _, _ in
                self?.refreshForCurrentState()
            }
            .store(in: &settingsCancellables)
    }

    deinit {
        loadTask?.cancel()
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
            presentation = .hidden
            return
        }

        presentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: .active(snapshot),
            lyrics: currentLyrics,
            offsetMilliseconds: currentOffsetMilliseconds,
            at: date
        )
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
        ignoredTrackStore.insert(currentTrackKey)
        try? cache.removeLyrics(for: currentTrackKey)
        currentLyrics = nil
        presentation = .hidden
    }

    func applyLyricsOverride(_ lyrics: TimedLyrics, for snapshot: MediaPlaybackSnapshot) {
        let trackKey = LyricsTrackKey(snapshot: snapshot)
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
            currentTrackKey = trackKey
            currentLyrics = nil
            presentation = .hidden
            loadTask?.cancel()
            loadTask = nil
            return
        }

        if currentTrackKey != trackKey {
            currentTrackKey = trackKey
            currentLyrics = nil
            currentOffsetMilliseconds = offsetStore.offset(for: trackKey)
            presentation = .hidden
            loadTask?.cancel()
            loadTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let lyrics = await provider.lyrics(for: snapshot)
                self.completeLyricsLoad(lyrics, for: trackKey)
            }
            return
        }

        refreshPresentation()
    }

    func completeLyricsLoad(_ lyrics: TimedLyrics?, for trackKey: LyricsTrackKey) {
        guard currentTrackKey == trackKey else {
            return
        }

        currentLyrics = lyrics
        refreshPresentation()
    }

    private func resetPresentation(clearLyrics: Bool) {
        loadTask?.cancel()
        loadTask = nil
        if clearLyrics {
            currentLyrics = nil
            currentTrackKey = nil
        }
        presentation = .hidden
    }
}
