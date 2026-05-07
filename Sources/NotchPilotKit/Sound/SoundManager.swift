import AVFoundation
import Combine
import Foundation
import os

/// Coordinates sound playback for NotchPilot.
///
/// Owns the list of available packs, the active pack selection, and the actual
/// AVAudioPlayer instances. All callers go through ``SoundManager/shared``.
///
/// Behaviour summary (CESP §8):
///   - random selection from a category's sound array
///   - avoids repeating the last sound played in the same category
///   - respects the global `soundEnabled` toggle and per-category volume
///     (`soundTaskCompleteVolume`, `soundInputRequiredVolume`)
///   - no-ops if no pack is active or the active pack has no sounds for the
///     requested category (fire-and-forget; never blocks the caller)
@MainActor
public final class SoundManager: ObservableObject {
    public static let shared = SoundManager()

    @Published public private(set) var installedPacks: [LoadedSoundPack] = []
    @Published public private(set) var activePack: LoadedSoundPack?

    private let loader: SoundPackLoader
    private let store: SettingsStore
    private let bundleLookup: () -> URL?
    private let logger = Logger(subsystem: "com.notchpilot.sound", category: "SoundManager")

    /// AVAudioPlayer instances must live for the duration of playback or they
    /// are silently deallocated mid-sound.
    private var retainedPlayers: [AVAudioPlayer] = []
    private var lastPlayedURLByCategory: [CESPCategory: URL] = [:]
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    private convenience init() {
        self.init(
            loader: SoundPackLoader(),
            store: .shared,
            bundleLookup: {
                Bundle.module.url(
                    forResource: "openpeon",
                    withExtension: "json",
                    subdirectory: "Sounds/builtin"
                )
            }
        )
    }

    /// Designated initializer used by tests to inject fakes.
    public init(
        loader: SoundPackLoader,
        store: SettingsStore,
        bundleLookup: @escaping () -> URL?
    ) {
        self.loader = loader
        self.store = store
        self.bundleLookup = bundleLookup
        refreshInstalledPacks()
        observeStoreChanges()
    }

    // MARK: - Public API

    /// Rescans available packs. Called automatically on init and after import.
    public func refreshInstalledPacks() {
        var packs: [LoadedSoundPack] = []
        if let builtIn = loadBuiltInPack() {
            packs.append(builtIn)
        }
        let disk = loader.discoverPacks()
        // De-duplicate by id; built-in wins if the user installed a pack with
        // the same name under ~/.openpeon/packs.
        let existingIDs = Set(packs.map(\.id))
        for pack in disk where existingIDs.contains(pack.id) == false {
            packs.append(pack)
        }
        installedPacks = packs

        let preferredID = store.soundActivePackID
        if preferredID.isEmpty == false,
           let match = packs.first(where: { $0.id == preferredID })
        {
            activePack = match
        } else {
            activePack = packs.first
        }
    }

    /// Changes the active pack and persists the choice.
    public func setActivePack(id: String) {
        guard let match = installedPacks.first(where: { $0.id == id }) else { return }
        activePack = match
        store.soundActivePackID = id
    }

    /// Validates the folder at `sourceURL` as a CESP pack, copies it into
    /// `~/.openpeon/packs/<id>/`, and rescans installed packs so the new pack
    /// appears in the picker. Returns the loaded pack on success.
    @discardableResult
    public func importPack(from sourceURL: URL) throws -> LoadedSoundPack {
        let validated = try loader.loadPack(at: sourceURL)
        let fm = FileManager.default
        guard let packsRoot = SoundPackLoader.defaultSearchRoots().first else {
            throw SoundPackLoaderError.manifestNotFound(sourceURL)
        }

        try fm.createDirectory(at: packsRoot, withIntermediateDirectories: true)

        let target = packsRoot.appendingPathComponent(validated.id, isDirectory: true)
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.copyItem(at: sourceURL, to: target)

        refreshInstalledPacks()
        return validated
    }

    /// Plays a CESP category. No-ops if sound is disabled, no pack is active,
    /// or the active pack has no sounds for the requested category.
    public func play(_ category: CESPCategory) {
        guard store.soundEnabled else { return }
        guard let pack = activePack else { return }
        let urls = pack.soundURLs(for: category)
        guard urls.isEmpty == false else { return }

        let chosen = pickURL(from: urls, category: category)

        do {
            let player = try AVAudioPlayer(contentsOf: chosen)
            player.volume = Float(clampedVolume(volume(for: category)))
            player.prepareToPlay()
            guard player.play() else {
                logger.warning(
                    "SoundManager: AVAudioPlayer.play() returned false for \(chosen.lastPathComponent, privacy: .public)"
                )
                return
            }
            retainedPlayers.append(player)
            pruneFinishedPlayers()
        } catch {
            logger.error(
                "SoundManager failed to play \(chosen.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Selection

    /// Picks a URL, avoiding the one most recently played in the same category,
    /// and records it as the new last-played so the next call can avoid it too.
    /// Exposed `internal` so unit tests can validate the no-repeat contract
    /// without driving AVAudioPlayer.
    func pickURL(from urls: [URL], category: CESPCategory) -> URL {
        let chosen: URL
        if urls.count <= 1 {
            chosen = urls[0]
        } else {
            let last = lastPlayedURLByCategory[category]
            let candidates = urls.filter { $0 != last }
            let pool = candidates.isEmpty ? urls : candidates
            chosen = pool.randomElement() ?? urls[0]
        }
        lastPlayedURLByCategory[category] = chosen
        return chosen
    }

    // MARK: - Private

    private func observeStoreChanges() {
        store.$soundActivePackID
            .dropFirst()
            .sink { [weak self] id in
                guard let self else { return }
                self.activePack = self.installedPacks.first(where: { $0.id == id })
                    ?? self.installedPacks.first
            }
            .store(in: &cancellables)
    }

    private func loadBuiltInPack() -> LoadedSoundPack? {
        guard let manifestURL = bundleLookup() else {
            logger.notice("SoundManager: no built-in manifest in bundle")
            return nil
        }
        let packRoot = manifestURL.deletingLastPathComponent()
        do {
            return try loader.loadPack(at: packRoot)
        } catch {
            logger.notice("SoundManager: built-in pack skipped (\(String(describing: error), privacy: .public))")
            return nil
        }
    }

    /// Resolved URL of the bundled built-in `openpeon.json` manifest, or nil
    /// if SwiftPM resource processing failed to ship it. Internal so tests can
    /// confirm the resource pipeline is wired without going through the
    /// global `shared` singleton.
    static var builtInManifestURL: URL? {
        Bundle.module.url(
            forResource: "openpeon",
            withExtension: "json",
            subdirectory: "Sounds/builtin"
        )
    }

    private func pruneFinishedPlayers() {
        retainedPlayers.removeAll { $0.isPlaying == false }
    }

    private func clampedVolume(_ raw: Double) -> Double {
        max(0.0, min(1.0, raw))
    }

    /// Maps a CESP category to the user-controlled volume slider.
    ///
    /// Only `.taskComplete` and `.inputRequired` are surfaced in the UI today;
    /// every other category falls back to the task-complete slider so the
    /// generic "task finished"-style cues stay tied to the same user control.
    private func volume(for category: CESPCategory) -> Double {
        switch category {
        case .inputRequired:
            return store.soundInputRequiredVolume
        case .sessionStart,
             .taskAcknowledge,
             .taskComplete,
             .taskError,
             .resourceLimit,
             .userSpam,
             .sessionEnd,
             .taskProgress:
            return store.soundTaskCompleteVolume
        }
    }
}
