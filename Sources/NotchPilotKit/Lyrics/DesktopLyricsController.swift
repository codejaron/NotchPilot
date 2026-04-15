import Combine
import Foundation

@MainActor
final class DesktopLyricsController: ObservableObject {
    @Published private(set) var presentation: DesktopLyricsPresentation = .hidden

    private let settingsStore: SettingsStore
    private let provider: LyricsProviding
    private let cache: LyricsCaching
    private let ignoredTrackStore: LyricsTrackIgnoring

    private var currentPlaybackState: MediaPlaybackState = .idle
    private var currentTrackKey: LyricsTrackKey?
    private var currentLyrics: TimedLyrics?
    private var loadTask: Task<Void, Never>?
    private var settingsCancellables: Set<AnyCancellable> = []

    init(
        settingsStore: SettingsStore = .shared,
        provider: LyricsProviding,
        cache: LyricsCaching,
        ignoredTrackStore: LyricsTrackIgnoring
    ) {
        self.settingsStore = settingsStore
        self.provider = provider
        self.cache = cache
        self.ignoredTrackStore = ignoredTrackStore

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
        presentation = DesktopLyricsPresentationResolver.resolve(
            playbackState: currentPlaybackState,
            lyrics: currentLyrics,
            at: date
        )
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

        guard case let .active(snapshot) = currentPlaybackState,
              snapshot.isPlaying,
              DesktopLyricsPlaybackFilter.isEligible(snapshot) else {
            resetPresentation(clearLyrics: false)
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

    private func completeLyricsLoad(_ lyrics: TimedLyrics?, for trackKey: LyricsTrackKey) {
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
