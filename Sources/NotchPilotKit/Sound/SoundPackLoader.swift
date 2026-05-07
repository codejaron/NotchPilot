import Foundation

public enum SoundPackLoaderError: Error, Equatable, Sendable, CustomStringConvertible {
    case manifestNotFound(URL)
    case manifestDecode(String)
    case invalidCespVersion(String)
    case invalidPackName(String)
    case pathEscapesRoot(String)
    case invalidFileName(String)
    case unsupportedAudioFormat(String)
    case fileMissing(String)
    case fileTooLarge(String, bytes: Int)
    case packTooLarge(bytes: Int)
    case invalidAudioHeader(String)

    public var description: String {
        switch self {
        case let .manifestNotFound(url):
            return "openpeon.json not found in pack at \(url.path)"
        case let .manifestDecode(detail):
            return "Failed to decode manifest: \(detail)"
        case let .invalidCespVersion(value):
            return "Unsupported cesp_version: \(value)"
        case let .invalidPackName(value):
            return "Invalid pack name '\(value)' (must match [a-z0-9][a-z0-9_-]*)"
        case let .pathEscapesRoot(value):
            return "Sound path '\(value)' escapes pack root"
        case let .invalidFileName(value):
            return "Sound file name '\(value)' contains disallowed characters"
        case let .unsupportedAudioFormat(value):
            return "Unsupported audio format for '\(value)' (only .wav and .mp3 are playable on macOS)"
        case let .fileMissing(value):
            return "Audio file not found: \(value)"
        case let .fileTooLarge(value, bytes):
            return "Audio file '\(value)' exceeds 1 MB cap (\(bytes) bytes)"
        case let .packTooLarge(bytes):
            return "Pack exceeds 50 MB cap (\(bytes) bytes)"
        case let .invalidAudioHeader(value):
            return "Audio file '\(value)' has invalid header bytes"
        }
    }
}

/// Loads CESP v1.0 sound packs from disk with strict safety validation.
///
/// Never trusts the contents of a pack directory. Verifies:
///   - `cesp_version == "1.0"`
///   - pack `name` matches `^[a-z0-9][a-z0-9_-]{0,63}$`
///   - every sound path stays inside the pack root (no `..` traversal, no symlink escape)
///   - file names match `^[a-zA-Z0-9._-]+$` (CESP §4.3)
///   - extension is `.wav` or `.mp3` (OGG skipped: not native on macOS AVAudioPlayer)
///   - each file ≤ 1 MB, total pack ≤ 50 MB
///   - magic bytes match the declared extension (CESP §4.4)
///
/// Unknown (non-CESP) category names are silently skipped so forward-compatible
/// packs still load. Categories with zero valid sounds are omitted from the
/// resolved result.
public struct SoundPackLoader {
    public static let manifestFileName = "openpeon.json"
    public static let supportedCespVersion = "1.0"
    public static let maxFileBytes = 1 * 1024 * 1024
    public static let maxPackBytes = 50 * 1024 * 1024
    public static let allowedExtensions: Set<String> = ["wav", "mp3"]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Loads and validates a single pack located at `packRoot`.
    public func loadPack(at packRoot: URL) throws -> LoadedSoundPack {
        let manifest = try decodeManifest(at: packRoot)

        guard manifest.cespVersion == Self.supportedCespVersion else {
            throw SoundPackLoaderError.invalidCespVersion(manifest.cespVersion)
        }

        guard matchesPackName(manifest.name) else {
            throw SoundPackLoaderError.invalidPackName(manifest.name)
        }

        var resolved: [CESPCategory: [URL]] = [:]
        var totalBytes = 0

        let canonicalRoot = canonicalPath(of: packRoot)

        for (categoryName, entry) in manifest.categories {
            // Unknown category names are valid per spec §1.3 — silently skip.
            guard let category = CESPCategory(rawValue: categoryName) else { continue }

            var urls: [URL] = []
            for sound in entry.sounds {
                let url = try validate(
                    soundRelativePath: sound.file,
                    packRoot: packRoot,
                    canonicalRoot: canonicalRoot,
                    totalBytesSoFar: &totalBytes
                )
                urls.append(url)
            }
            if urls.isEmpty == false {
                resolved[category] = urls
            }
        }

        return LoadedSoundPack(
            id: manifest.name,
            manifest: manifest,
            rootURL: packRoot,
            soundsByCategory: resolved
        )
    }

    /// Scans standard search roots and returns every successfully-loaded pack.
    /// Packs that fail validation are skipped (not thrown) so a single bad pack
    /// cannot brick the whole setting.
    public func discoverPacks(in searchRoots: [URL] = Self.defaultSearchRoots()) -> [LoadedSoundPack] {
        var results: [LoadedSoundPack] = []
        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            let children = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for candidate in children {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                if let pack = try? loadPack(at: candidate) {
                    results.append(pack)
                }
            }
        }
        return results
    }

    /// Standard search roots. Matches `peon-ping` so packs already installed
    /// for Claude Code hooks are auto-discovered by NotchPilot.
    public static func defaultSearchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".openpeon", isDirectory: true)
                .appendingPathComponent("packs", isDirectory: true),
        ]
    }

    // MARK: - Manifest

    private func decodeManifest(at packRoot: URL) throws -> CESPManifest {
        let manifestURL = packRoot.appendingPathComponent(Self.manifestFileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SoundPackLoaderError.manifestNotFound(packRoot)
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(CESPManifest.self, from: data)
        } catch {
            throw SoundPackLoaderError.manifestDecode(error.localizedDescription)
        }
    }

    // MARK: - Validation

    private func validate(
        soundRelativePath: String,
        packRoot: URL,
        canonicalRoot: String,
        totalBytesSoFar: inout Int
    ) throws -> URL {
        // 1. Reject obvious traversal patterns before touching disk.
        guard soundRelativePath.contains("..") == false else {
            throw SoundPackLoaderError.pathEscapesRoot(soundRelativePath)
        }

        let trimmed = soundRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidate = packRoot.appendingPathComponent(trimmed)
        let canonicalCandidate = canonicalPath(of: candidate)

        // 2. Resolved path must live strictly below the pack root.
        let boundary = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        guard canonicalCandidate.hasPrefix(boundary) else {
            throw SoundPackLoaderError.pathEscapesRoot(soundRelativePath)
        }

        // 3. Filename must match CESP §4.3 whitelist.
        let fileName = candidate.lastPathComponent
        guard matchesFileName(fileName) else {
            throw SoundPackLoaderError.invalidFileName(fileName)
        }

        // 4. Extension must be one we can actually play on macOS.
        let ext = candidate.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            throw SoundPackLoaderError.unsupportedAudioFormat(fileName)
        }

        // 5. File must exist.
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw SoundPackLoaderError.fileMissing(fileName)
        }

        // 6. Size caps.
        let size: Int
        do {
            let attrs = try fileManager.attributesOfItem(atPath: candidate.path)
            size = (attrs[.size] as? Int) ?? 0
        } catch {
            throw SoundPackLoaderError.fileMissing(fileName)
        }
        if size > Self.maxFileBytes {
            throw SoundPackLoaderError.fileTooLarge(fileName, bytes: size)
        }
        totalBytesSoFar += size
        if totalBytesSoFar > Self.maxPackBytes {
            throw SoundPackLoaderError.packTooLarge(bytes: totalBytesSoFar)
        }

        // 7. Magic-byte sniff (CESP §4.4). Reject payloads that don't look like
        // what their extension claims.
        guard let magic = readMagicBytes(at: candidate),
              magicBytesMatch(ext: ext, header: magic)
        else {
            throw SoundPackLoaderError.invalidAudioHeader(fileName)
        }

        return candidate
    }

    private func canonicalPath(of url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func readMagicBytes(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: 4)
    }

    private func magicBytesMatch(ext: String, header: Data) -> Bool {
        guard header.isEmpty == false else { return false }
        switch ext {
        case "wav":
            return header.starts(with: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        case "mp3":
            if header.starts(with: [0x49, 0x44, 0x33]) {         // "ID3" (ID3v2 tag)
                return true
            }
            // MPEG-1/2 frame sync: 11 bits of 1s (0xFFE0 mask).
            if header.count >= 2,
               header[0] == 0xFF,
               (header[1] & 0xE0) == 0xE0
            {
                return true
            }
            return false
        default:
            return false
        }
    }

    // MARK: - Regex helpers

    private func matchesPackName(_ value: String) -> Bool {
        guard value.count <= 64 else { return false }
        return value.range(
            of: #"^[a-z0-9][a-z0-9_-]*$"#,
            options: .regularExpression
        ) != nil
    }

    private func matchesFileName(_ value: String) -> Bool {
        value.range(
            of: #"^[a-zA-Z0-9._-]+$"#,
            options: .regularExpression
        ) != nil
    }
}
