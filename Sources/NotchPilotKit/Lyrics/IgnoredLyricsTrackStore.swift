import Foundation

protocol LyricsTrackIgnoring: AnyObject {
    func contains(_ key: LyricsTrackKey) -> Bool
    func insert(_ key: LyricsTrackKey)
    func remove(_ key: LyricsTrackKey)
}

final class IgnoredLyricsTrackStore: LyricsTrackIgnoring {
    private enum Key {
        static let ignoredTrackStorage = "media.ignoredLyricsTracks"
    }

    private let defaults: UserDefaults
    private var ignoredTrackIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ignoredTrackIDs = Set(defaults.stringArray(forKey: Key.ignoredTrackStorage) ?? [])
    }

    func contains(_ key: LyricsTrackKey) -> Bool {
        ignoredTrackIDs.contains(key.storageIdentifier)
    }

    func insert(_ key: LyricsTrackKey) {
        ignoredTrackIDs.insert(key.storageIdentifier)
        defaults.set(Array(ignoredTrackIDs).sorted(), forKey: Key.ignoredTrackStorage)
    }

    func remove(_ key: LyricsTrackKey) {
        ignoredTrackIDs.remove(key.storageIdentifier)
        defaults.set(Array(ignoredTrackIDs).sorted(), forKey: Key.ignoredTrackStorage)
    }
}
