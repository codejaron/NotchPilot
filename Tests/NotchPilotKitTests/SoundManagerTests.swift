import XCTest

@testable import NotchPilotKit

final class SoundManagerPickTests: XCTestCase {
    @MainActor
    func testPickURLReturnsTheLoneEntryWhenOnlyOne() {
        let manager = makeIsolatedManager()
        let only = URL(fileURLWithPath: "/tmp/a.wav")
        XCTAssertEqual(manager.pickURL(from: [only], category: .taskComplete), only)
    }

    @MainActor
    func testPickURLAvoidsRepeatingTheLastPlayed() {
        let manager = makeIsolatedManager()
        let a = URL(fileURLWithPath: "/tmp/a.wav")
        let b = URL(fileURLWithPath: "/tmp/b.wav")

        // After "playing" a, the next pick from {a, b} must be b.
        manager.recordLastPlayedForTest(url: a, category: .taskComplete)
        XCTAssertEqual(manager.pickURL(from: [a, b], category: .taskComplete), b)
    }

    @MainActor
    func testPickURLFallsBackWhenAllCandidatesEqualLast() {
        let manager = makeIsolatedManager()
        let a = URL(fileURLWithPath: "/tmp/a.wav")
        manager.recordLastPlayedForTest(url: a, category: .inputRequired)

        // Only one URL exists and it equals last — must still return it
        // instead of returning nil.
        XCTAssertEqual(manager.pickURL(from: [a], category: .inputRequired), a)
    }

    // MARK: - Helpers

    @MainActor
    private func makeIsolatedManager() -> SoundManager {
        // Bundle lookup that returns nil so the built-in pack can't bleed into
        // tests if the resource happens to exist.
        SoundManager(
            loader: SoundPackLoader(),
            store: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            bundleLookup: { nil }
        )
    }
}

final class SoundManagerImportTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    @MainActor
    func testImportPackCopiesOnlyManifestAndReferencedSounds() throws {
        let source = try writePackWithExtraFiles(name: "clean-import")
        let installRoot = tempRoot.appendingPathComponent("installed", isDirectory: true)
        let manager = makeIsolatedManager(installRoot: installRoot)

        let loaded = try manager.importPack(from: source)

        let target = installRoot.appendingPathComponent("clean-import", isDirectory: true)
        XCTAssertEqual(loaded.rootURL.standardizedFileURL, target.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: target.appendingPathComponent(SoundPackLoader.manifestFileName).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("sounds/done.wav").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("sounds/unreferenced.wav").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("junk.bin").path
        ))
    }

    @MainActor
    private func makeIsolatedManager(installRoot: URL) -> SoundManager {
        SoundManager(
            loader: SoundPackLoader(),
            store: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            bundleLookup: { nil },
            installedPacksRoot: { installRoot }
        )
    }

    private func writePackWithExtraFiles(name: String) throws -> URL {
        let pack = tempRoot.appendingPathComponent(name, isDirectory: true)
        let sounds = pack.appendingPathComponent("sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)

        try validRIFFBytes().write(to: sounds.appendingPathComponent("done.wav"))
        try validRIFFBytes().write(to: sounds.appendingPathComponent("unreferenced.wav"))
        try Data(repeating: 0x7F, count: 16).write(to: pack.appendingPathComponent("junk.bin"))

        let manifestObject: [String: Any] = [
            "cesp_version": "1.0",
            "name": name,
            "display_name": name,
            "version": "1.0.0",
            "categories": [
                "task.complete": [
                    "sounds": [
                        ["file": "sounds/done.wav", "label": "Done"],
                    ],
                ],
            ],
        ]

        let manifestData = try JSONSerialization.data(withJSONObject: manifestObject, options: [.prettyPrinted])
        try manifestData.write(to: pack.appendingPathComponent(SoundPackLoader.manifestFileName))
        return pack
    }

    private func validRIFFBytes() -> Data {
        Data([
            0x52, 0x49, 0x46, 0x46,
            0x24, 0x00, 0x00, 0x00,
            0x57, 0x41, 0x56, 0x45,
        ])
    }
}

extension SoundManager {
    /// Test-only seam for the `lastPlayedURL` cache so we don't have to
    /// trigger real audio playback to verify the no-repeat contract.
    func recordLastPlayedForTest(url: URL, category: CESPCategory) {
        // Reach into private storage via a public path: pickURL records the
        // chosen URL in the cache, so we can prime the cache by playing-then-
        // discarding through it. This requires only a single entry, so we
        // call pickURL with that one URL to make it the recorded last.
        _ = pickURL(from: [url], category: category)
    }
}
