import Foundation

/// A validated sound pack ready for playback.
///
/// All `soundsByCategory` URLs have already been through `SoundPackLoader`'s
/// safety checks (path-traversal guard, file-name whitelist, size caps, magic
/// bytes). Callers can play them without re-validating.
public struct LoadedSoundPack: Sendable, Equatable, Identifiable {
    public let id: String
    public let manifest: CESPManifest
    public let rootURL: URL
    public let soundsByCategory: [CESPCategory: [URL]]

    public init(
        id: String,
        manifest: CESPManifest,
        rootURL: URL,
        soundsByCategory: [CESPCategory: [URL]]
    ) {
        self.id = id
        self.manifest = manifest
        self.rootURL = rootURL
        self.soundsByCategory = soundsByCategory
    }

    public func soundURLs(for category: CESPCategory) -> [URL] {
        soundsByCategory[category] ?? []
    }

    public var displayName: String {
        manifest.displayName
    }

    public var supportedCategories: Set<CESPCategory> {
        Set(soundsByCategory.keys)
    }
}
