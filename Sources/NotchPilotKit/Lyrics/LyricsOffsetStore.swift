import Foundation

protocol LyricsOffsetStoring: AnyObject {
    func offset(for key: LyricsTrackKey) -> Int
    func setOffset(_ offset: Int, for key: LyricsTrackKey)
}

final class LyricsOffsetStore: LyricsOffsetStoring {
    private enum Key {
        static let offsetStorage = "media.lyricsOffsets"
    }

    private let defaults: UserDefaults
    private var offsets: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.offsets = (defaults.dictionary(forKey: Key.offsetStorage) as? [String: Int]) ?? [:]
    }

    func offset(for key: LyricsTrackKey) -> Int {
        offsets[key.storageIdentifier] ?? 0
    }

    func setOffset(_ offset: Int, for key: LyricsTrackKey) {
        if offset == 0 {
            offsets.removeValue(forKey: key.storageIdentifier)
        } else {
            offsets[key.storageIdentifier] = offset
        }
        defaults.set(offsets, forKey: Key.offsetStorage)
    }
}
