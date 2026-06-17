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

        XCTAssertEqual(reloaded.title, "Project")
        XCTAssertEqual(reloaded.body, "# Project Plan\n\nShip the notes plugin.")
        XCTAssertEqual(reloaded.createdAt, createdAt)
        XCTAssertEqual(reloaded.updatedAt, updatedAt)
        XCTAssertEqual(reloaded.lastOpenedAt, openedAt)
        XCTAssertEqual(index.lastOpenedNoteID, note.id)
        let record = try XCTUnwrap(index.notes.first(where: { $0.id == note.id }))
        XCTAssertEqual(record.directoryName, "Project")
        XCTAssertEqual(record.markdownFileName, "Project.md")
        XCTAssertEqual(
            try String(contentsOf: rootURL.appendingPathComponent("notes/Project/Project.md")),
            "# Project Plan\n\nShip the notes plugin."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/Untitled").path))
    }

    func testManualTitleSurvivesBodyEdits() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        var note = try store.createNote(now: Date(timeIntervalSince1970: 10))

        note = try store.renameNote(noteID: note.id, title: "Manual Name", now: Date(timeIntervalSince1970: 20))
        note.body = "# Body Title\nContent"
        note = try store.saveNote(note, now: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(note.title, "Manual Name")
        XCTAssertTrue(note.isTitleManuallySet)
        XCTAssertEqual(
            try String(contentsOf: rootURL.appendingPathComponent("notes/Manual Name/Manual Name.md")),
            "# Body Title\nContent"
        )
    }

    func testDuplicateTitlesUseFinderStyleNumericSuffixes() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let first = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let second = try store.createNote(now: Date(timeIntervalSince1970: 20))

        _ = try store.renameNote(noteID: first.id, title: "Project", now: Date(timeIntervalSince1970: 30))
        _ = try store.renameNote(noteID: second.id, title: "Project", now: Date(timeIntervalSince1970: 40))

        let index = try store.loadIndex()
        let firstRecord = try XCTUnwrap(index.notes.first(where: { $0.id == first.id }))
        let secondRecord = try XCTUnwrap(index.notes.first(where: { $0.id == second.id }))

        XCTAssertEqual(firstRecord.directoryName, "Project")
        XCTAssertEqual(firstRecord.markdownFileName, "Project.md")
        XCTAssertEqual(secondRecord.directoryName, "Project 2")
        XCTAssertEqual(secondRecord.markdownFileName, "Project 2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/Project/Project.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/Project 2/Project 2.md").path))
    }

    func testTitleBackedPathsAreSanitizedForFileSystemNames() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))

        _ = try store.renameNote(noteID: note.id, title: "  Plan/Ship:Now\nToday  ", now: Date(timeIntervalSince1970: 20))

        let record = try XCTUnwrap(try store.loadIndex().notes.first(where: { $0.id == note.id }))
        XCTAssertEqual(record.title, "Plan/Ship:Now\nToday")
        XCTAssertEqual(record.directoryName, "Plan Ship Now Today")
        XCTAssertEqual(record.markdownFileName, "Plan Ship Now Today.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/Plan Ship Now Today/Plan Ship Now Today.md").path))
    }

    func testDerivedTitleBackedFileNamesAreLimitedToReadableLength() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        var note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let longFirstSentence = "This is a very long first sentence that should not become an equally long file name"
        let expectedTitle = String(longFirstSentence.prefix(ScratchpadNote.maximumDerivedTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(ScratchpadNote.maximumDerivedTitleLength, 8)

        note.body = "# \(longFirstSentence)\n\nMore detail follows."
        note = try store.saveNote(note, now: Date(timeIntervalSince1970: 20))

        let record = try XCTUnwrap(try store.loadIndex().notes.first(where: { $0.id == note.id }))
        XCTAssertEqual(note.title, expectedTitle)
        XCTAssertEqual(record.directoryName, expectedTitle)
        XCTAssertEqual(record.markdownFileName, "\(expectedTitle).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("notes/\(expectedTitle)/\(expectedTitle).md").path))
    }

    func testBlankUntitledNoteIsDiscardedWhenPristine() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let noteDirectory = store.noteDirectoryURL(forNoteID: note.id)

        XCTAssertTrue(try store.discardIfPristine(noteID: note.id))
        XCTAssertNil(try store.loadNote(id: note.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteDirectory.path))
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.noteDirectoryURL(forNoteID: note.id).appendingPathComponent("attachments/diagram.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.noteDirectoryURL(forNoteID: note.id).appendingPathComponent("attachments/diagram 2.png").path))
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.noteDirectoryURL(forNoteID: note.id).appendingPathComponent("attachments/sample file.txt").path))
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
