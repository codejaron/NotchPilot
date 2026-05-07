import XCTest

@testable import NotchPilotKit

final class CESPManifestDecodingTests: XCTestCase {
    func testDecodesMinimalManifest() throws {
        let json = #"""
        {
          "cesp_version": "1.0",
          "name": "demo",
          "display_name": "Demo Pack",
          "version": "1.0.0",
          "categories": {
            "task.complete": {
              "sounds": [
                { "file": "sounds/done.wav", "label": "Done" }
              ]
            }
          }
        }
        """#

        let manifest = try JSONDecoder().decode(CESPManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.cespVersion, "1.0")
        XCTAssertEqual(manifest.name, "demo")
        XCTAssertEqual(manifest.displayName, "Demo Pack")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.categories["task.complete"]?.sounds.first?.file, "sounds/done.wav")
        XCTAssertEqual(manifest.categories["task.complete"]?.sounds.first?.label, "Done")
    }

    func testDecodesFullManifest() throws {
        let json = #"""
        {
          "cesp_version": "1.0",
          "name": "fancy-pack",
          "display_name": "Fancy",
          "version": "2.1.0",
          "description": "Test pack",
          "author": { "name": "Alice", "github": "alice" },
          "license": "CC0-1.0",
          "language": "en",
          "homepage": "https://example.com",
          "tags": ["retro", "8bit"],
          "categories": {
            "input.required": {
              "sounds": [
                { "file": "sounds/q.mp3", "label": "Q", "sha256": "deadbeef" }
              ]
            }
          }
        }
        """#

        let manifest = try JSONDecoder().decode(CESPManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.author?.name, "Alice")
        XCTAssertEqual(manifest.author?.github, "alice")
        XCTAssertEqual(manifest.license, "CC0-1.0")
        XCTAssertEqual(manifest.tags, ["retro", "8bit"])
        XCTAssertEqual(manifest.categories["input.required"]?.sounds.first?.sha256, "deadbeef")
    }
}

final class SoundPackLoaderTests: XCTestCase {
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

    // MARK: - Happy paths

    func testLoadsValidPack() throws {
        let pack = try writePack(
            name: "happy-pack",
            categories: [
                "task.complete": [("done.wav", validRIFFBytes())],
            ]
        )

        let loaded = try SoundPackLoader().loadPack(at: pack)
        XCTAssertEqual(loaded.id, "happy-pack")
        XCTAssertEqual(loaded.soundURLs(for: .taskComplete).count, 1)
        XCTAssertTrue(loaded.soundURLs(for: .inputRequired).isEmpty)
    }

    func testSilentlySkipsUnknownCategories() throws {
        // Unknown category names are valid per spec §1.3 — the player should
        // load the rest of the pack, not throw.
        let pack = try writePack(
            name: "future-pack",
            categories: [
                "task.complete": [("done.wav", validRIFFBytes())],
                "unknown.future": [("ignore.wav", validRIFFBytes())],
            ]
        )

        let loaded = try SoundPackLoader().loadPack(at: pack)
        XCTAssertEqual(loaded.soundURLs(for: .taskComplete).count, 1)
        XCTAssertEqual(loaded.supportedCategories, [.taskComplete])
    }

    // MARK: - Failure paths (each demonstrates one safety guarantee)

    func testRejectsPackWithBadCespVersion() throws {
        let pack = try writePack(name: "bad-version", cespVersion: "2.0", categories: [:])
        XCTAssertThrowsError(try SoundPackLoader().loadPack(at: pack)) { error in
            guard case let SoundPackLoaderError.invalidCespVersion(value) = error else {
                XCTFail("Expected invalidCespVersion, got \(error)"); return
            }
            XCTAssertEqual(value, "2.0")
        }
    }

    func testRejectsPackWithUppercaseName() throws {
        let pack = try writePack(name: "Bad-Name", categories: [:])
        XCTAssertThrowsError(try SoundPackLoader().loadPack(at: pack)) { error in
            guard case SoundPackLoaderError.invalidPackName = error else {
                XCTFail("Expected invalidPackName, got \(error)"); return
            }
        }
    }

    func testRejectsPathTraversalInSoundFile() throws {
        let pack = try writePack(
            name: "evil-pack",
            categories: [
                // Try to escape via ../ — must be caught before disk access.
                "task.complete": [("../escape.wav", validRIFFBytes())],
            ]
        )

        XCTAssertThrowsError(try SoundPackLoader().loadPack(at: pack)) { error in
            guard case SoundPackLoaderError.pathEscapesRoot = error else {
                XCTFail("Expected pathEscapesRoot, got \(error)"); return
            }
        }
    }

    func testRejectsUnsupportedExtension() throws {
        let pack = try writePack(
            name: "ogg-pack",
            categories: [
                "task.complete": [("clip.ogg", Data([0x4F, 0x67, 0x67, 0x53]))], // "OggS"
            ]
        )

        XCTAssertThrowsError(try SoundPackLoader().loadPack(at: pack)) { error in
            guard case SoundPackLoaderError.unsupportedAudioFormat = error else {
                XCTFail("Expected unsupportedAudioFormat, got \(error)"); return
            }
        }
    }

    func testRejectsInvalidMagicBytes() throws {
        let pack = try writePack(
            name: "fake-wav",
            categories: [
                // Lies about being a wav: extension says wav, header is junk.
                "task.complete": [("fake.wav", Data([0x00, 0x01, 0x02, 0x03]))],
            ]
        )

        XCTAssertThrowsError(try SoundPackLoader().loadPack(at: pack)) { error in
            guard case SoundPackLoaderError.invalidAudioHeader = error else {
                XCTFail("Expected invalidAudioHeader, got \(error)"); return
            }
        }
    }

    func testRejectsFileWithSpacesInName() throws {
        let pack = try writePack(
            name: "spaces",
            categories: [
                "task.complete": [("bad name.wav", validRIFFBytes())],
            ]
        )

        XCTAssertThrowsError(try SoundPackLoader().loadPack(at: pack)) { error in
            guard case SoundPackLoaderError.invalidFileName = error else {
                XCTFail("Expected invalidFileName, got \(error)"); return
            }
        }
    }

    // MARK: - Bundle integration

    @MainActor
    func testBuiltInPackLoadsFromBundle() throws {
        guard let manifestURL = SoundManager.builtInManifestURL else {
            XCTFail("Built-in openpeon.json not shipped — check Package.swift resources")
            return
        }
        let pack = try SoundPackLoader().loadPack(at: manifestURL.deletingLastPathComponent())
        XCTAssertEqual(pack.id, "notchpilot-builtin")
        XCTAssertEqual(pack.soundURLs(for: .taskComplete).count, 1)
        XCTAssertEqual(pack.soundURLs(for: .inputRequired).count, 1)
        XCTAssertEqual(pack.soundURLs(for: .taskComplete).first?.lastPathComponent, "confirmation_002.wav")
        XCTAssertEqual(pack.soundURLs(for: .inputRequired).first?.lastPathComponent, "question_002.wav")
    }

    func testRejectsPackMissingManifest() throws {
        let pack = tempRoot.appendingPathComponent("no-manifest", isDirectory: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        XCTAssertThrowsError(try SoundPackLoader().loadPack(at: pack)) { error in
            guard case SoundPackLoaderError.manifestNotFound = error else {
                XCTFail("Expected manifestNotFound, got \(error)"); return
            }
        }
    }

    // MARK: - Test fixtures

    /// Writes a pack at `tempRoot/<name>` and returns its URL. Sound files are
    /// written under `sounds/<filename>` and registered in the manifest.
    @discardableResult
    private func writePack(
        name: String,
        cespVersion: String = "1.0",
        categories: [String: [(String, Data)]]
    ) throws -> URL {
        let pack = tempRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)

        let soundsDir = pack.appendingPathComponent("sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)

        // Write each audio file (skip path-traversal entries — they live as
        // strings in the manifest only).
        var manifestCategories: [String: [[String: String]]] = [:]
        for (category, sounds) in categories {
            var entries: [[String: String]] = []
            for (fileName, data) in sounds {
                let isTraversal = fileName.contains("..")
                if isTraversal == false {
                    let fileURL = soundsDir.appendingPathComponent(fileName)
                    try data.write(to: fileURL)
                }
                let manifestPath = isTraversal ? fileName : "sounds/\(fileName)"
                entries.append(["file": manifestPath, "label": fileName])
            }
            manifestCategories[category] = entries
        }

        let manifestObject: [String: Any] = [
            "cesp_version": cespVersion,
            "name": name,
            "display_name": name,
            "version": "1.0.0",
            "categories": manifestCategories.mapValues { ["sounds": $0] },
        ]

        let manifestURL = pack.appendingPathComponent(SoundPackLoader.manifestFileName)
        let data = try JSONSerialization.data(withJSONObject: manifestObject, options: [.prettyPrinted])
        try data.write(to: manifestURL)
        return pack
    }

    /// 12-byte minimal RIFF/WAVE header. Enough to pass magic-byte sniffing
    /// without bothering to be a playable file.
    private func validRIFFBytes() -> Data {
        Data([
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            0x24, 0x00, 0x00, 0x00, // chunk size (placeholder)
            0x57, 0x41, 0x56, 0x45, // "WAVE"
        ])
    }
}
