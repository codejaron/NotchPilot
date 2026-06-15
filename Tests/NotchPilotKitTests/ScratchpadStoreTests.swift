import XCTest
@testable import NotchPilotKit

final class ScratchpadStoreTests: XCTestCase {
    private var rootURL: URL!
    private var homeURL: URL!

    override func setUpWithError() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScratchpadStoreTests-\(UUID().uuidString)", isDirectory: true)
        rootURL = baseURL.appendingPathComponent("Scratchpad", isDirectory: true)
        homeURL = baseURL.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent())
        rootURL = nil
        homeURL = nil
    }

    func testDefaultRootUsesApplicationSupportScratchpadUnderHomeDirectory() {
        let store = ScratchpadStore(homeDirectoryURL: homeURL)

        XCTAssertEqual(
            store.rootURL,
            homeURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("NotchPilot", isDirectory: true)
                .appendingPathComponent("Scratchpad", isDirectory: true)
        )
    }

    func testCreateSaveReloadAndLastOpenedNote() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let createdAt = Date(timeIntervalSince1970: 10)
        let updatedAt = Date(timeIntervalSince1970: 20)
        let openedAt = Date(timeIntervalSince1970: 30)

        var note = try store.createNote(now: createdAt)
        note.body = "# Project Plan\n\nShip the notes plugin."
        note = try store.saveNote(note, now: updatedAt)
        try store.markOpened(noteID: note.id, now: openedAt)

        let reloadedStore = ScratchpadStore(rootURL: rootURL)
        let reloaded = try XCTUnwrap(reloadedStore.loadNote(id: note.id))
        let index = try reloadedStore.loadIndex()

        XCTAssertEqual(reloaded.title, "Project Plan")
        XCTAssertEqual(reloaded.body, "# Project Plan\n\nShip the notes plugin.")
        XCTAssertEqual(reloaded.createdAt, createdAt)
        XCTAssertEqual(reloaded.updatedAt, updatedAt)
        XCTAssertEqual(reloaded.lastOpenedAt, openedAt)
        XCTAssertEqual(index.lastOpenedNoteID, note.id)
        XCTAssertEqual(
            try String(contentsOf: rootURL.appendingPathComponent("notes/\(note.id)/note.md")),
            "# Project Plan\n\nShip the notes plugin."
        )
    }

    func testManualTitleSurvivesBodyEdits() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        var note = try store.createNote(now: Date(timeIntervalSince1970: 10))

        note = try store.renameNote(noteID: note.id, title: "Manual Name", now: Date(timeIntervalSince1970: 20))
        note.body = "# Body Title\nContent"
        note = try store.saveNote(note, now: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(note.title, "Manual Name")
        XCTAssertTrue(note.isTitleManuallySet)
    }

    func testBlankUntitledNoteIsDiscardedWhenPristine() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))

        XCTAssertTrue(try store.discardIfPristine(noteID: note.id))
        XCTAssertNil(try store.loadNote(id: note.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/\(note.id)").path))
    }

    func testBlankManualTitleNoteIsNotDiscarded() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))

        _ = try store.renameNote(noteID: note.id, title: "Keep Me", now: Date(timeIntervalSince1970: 20))

        XCTAssertFalse(try store.discardIfPristine(noteID: note.id))
        XCTAssertNotNil(try store.loadNote(id: note.id))
    }

    func testCopyAttachmentCreatesUniqueRelativePathsAndMetadata() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let source = rootURL.deletingLastPathComponent().appendingPathComponent("diagram.png")
        try Data("png".utf8).write(to: source)

        let first = try store.copyAttachment(
            from: source,
            toNoteID: note.id,
            now: Date(timeIntervalSince1970: 20)
        )
        let second = try store.copyAttachment(
            from: source,
            toNoteID: note.id,
            now: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(first.relativePath, "attachments/diagram.png")
        XCTAssertEqual(second.relativePath, "attachments/diagram 2.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/\(note.id)/attachments/diagram.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/\(note.id)/attachments/diagram 2.png").path))
        XCTAssertEqual(try store.loadNote(id: note.id)?.attachments.map(\.relativePath), [
            "attachments/diagram.png",
            "attachments/diagram 2.png",
        ])
    }

    func testMigratingExternalMarkdownLinksCopiesAccessibleFilesAndKeepsFailures() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let source = rootURL.deletingLastPathComponent().appendingPathComponent("sample file.txt")
        try Data("hello".utf8).write(to: source)
        let missing = rootURL.deletingLastPathComponent().appendingPathComponent("missing.txt")
        var note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        note.body = "[Sample](\(source.path))\n[Missing](\(missing.path))"
        note = try store.saveNote(note, now: Date(timeIntervalSince1970: 20))

        let result = try store.migrateExternalMarkdownLinks(now: Date(timeIntervalSince1970: 30))
        let migrated = try XCTUnwrap(store.loadNote(id: note.id))

        XCTAssertEqual(result.migratedCount, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(migrated.body, "[Sample](attachments/sample file.txt)\n[Missing](\(missing.path))")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/\(note.id)/attachments/sample file.txt").path))
    }

    func testExternalMarkdownFileLinkScannerReportsMissingAbsoluteFiles() throws {
        let existing = rootURL.deletingLastPathComponent().appendingPathComponent("existing.pdf")
        try Data("pdf".utf8).write(to: existing)
        let missing = rootURL.deletingLastPathComponent().appendingPathComponent("missing.pdf")
        let body = """
        [Existing](\(existing.path))
        ![Missing](\(missing.path))
        [Copied](attachments/copied.pdf)
        """

        XCTAssertEqual(
            ScratchpadStore.externalMarkdownFileURLs(in: body).map(\.path),
            [existing.path, missing.path]
        )
        XCTAssertEqual(
            ScratchpadStore.missingExternalMarkdownFileURLs(in: body).map(\.path),
            [missing.path]
        )
    }
}
