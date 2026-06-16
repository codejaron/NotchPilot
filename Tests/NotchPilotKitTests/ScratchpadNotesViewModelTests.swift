import XCTest
@testable import NotchPilotKit

final class ScratchpadNotesViewModelTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScratchpadNotesViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
    }

    @MainActor
    func testLoadSelectsLastOpenedNote() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let first = try makeNote(store: store, body: "# First", now: 10)
        let second = try makeNote(store: store, body: "# Second", now: 20)
        try store.markOpened(noteID: first.id, now: Date(timeIntervalSince1970: 30))
        try store.markOpened(noteID: second.id, now: Date(timeIntervalSince1970: 40))
        let viewModel = ScratchpadNotesViewModel(store: store)

        try viewModel.load()

        XCTAssertEqual(viewModel.selectedNote?.id, second.id)
        XCTAssertEqual(viewModel.notes.map(\.id), [second.id, first.id])
    }

    @MainActor
    func testLoadMarksDefaultNoteAsRecentlyOpened() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try makeNote(store: store, body: "# First", now: 10)
        let viewModel = ScratchpadNotesViewModel(store: store)

        try viewModel.load(now: Date(timeIntervalSince1970: 40))

        let reloaded = try XCTUnwrap(store.loadNote(id: note.id))
        XCTAssertEqual(reloaded.lastOpenedAt, Date(timeIntervalSince1970: 40))
        XCTAssertEqual(try store.loadIndex().lastOpenedNoteID, note.id)
    }

    @MainActor
    func testSelectingAnotherNoteDiscardsPristineEmptyNote() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let existing = try makeNote(store: store, body: "# Existing", now: 10)
        let viewModel = ScratchpadNotesViewModel(store: store)
        try viewModel.load()
        let empty = try viewModel.createNote(now: Date(timeIntervalSince1970: 20))

        try viewModel.selectNote(id: existing.id, now: Date(timeIntervalSince1970: 30))

        XCTAssertNil(try store.loadNote(id: empty.id))
        XCTAssertEqual(viewModel.selectedNote?.id, existing.id)
    }

    @MainActor
    func testSearchFiltersTitlesAndBodyPreview() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let first = try makeNote(store: store, body: "# Travel\nKyoto reservation", now: 10)
        let second = try makeNote(store: store, body: "# Work\nSprint notes", now: 20)
        let viewModel = ScratchpadNotesViewModel(store: store)
        try viewModel.load()

        viewModel.searchText = "kyoto"

        XCTAssertEqual(viewModel.filteredNotes.map(\.id), [first.id])

        viewModel.searchText = "work"

        XCTAssertEqual(viewModel.filteredNotes.map(\.id), [second.id])
    }

    @MainActor
    func testUpdatingSelectedBodyPersistsAndRegeneratesAutomaticTitle() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let viewModel = ScratchpadNotesViewModel(store: store)
        try viewModel.load()

        try viewModel.updateSelectedBody("# Fresh Title\nBody", now: Date(timeIntervalSince1970: 20))
        try viewModel.flushPendingSave()
        let reloaded = try XCTUnwrap(store.loadNote(id: note.id))

        XCTAssertEqual(reloaded.title, "Fresh Title")
        XCTAssertEqual(reloaded.body, "# Fresh Title\nBody")
        XCTAssertEqual(viewModel.selectedNote?.title, "Fresh Title")
    }

    @MainActor
    func testUpdatingSelectedBodyDebouncesDiskWriteUntilFlush() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let viewModel = ScratchpadNotesViewModel(store: store)
        try viewModel.load()

        try viewModel.updateSelectedBody("# Draft\nBody", now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(viewModel.selectedNote?.body, "# Draft\nBody")
        XCTAssertEqual(viewModel.selectedNote?.title, "Draft")
        XCTAssertEqual(try store.loadNote(id: note.id)?.body, "")

        try viewModel.flushPendingSave()

        XCTAssertEqual(try store.loadNote(id: note.id)?.body, "# Draft\nBody")
    }

    @MainActor
    func testReloadFlushesPendingBodyBeforeRefreshingFromDisk() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let viewModel = ScratchpadNotesViewModel(store: store)
        try viewModel.load()

        try viewModel.updateSelectedBody("# Kept Draft", now: Date(timeIntervalSince1970: 20))
        try viewModel.load()

        XCTAssertEqual(try store.loadNote(id: note.id)?.body, "# Kept Draft")
        XCTAssertEqual(viewModel.selectedNote?.body, "# Kept Draft")
    }

    @MainActor
    func testInsertAttachmentCopiesFileAndUsesImageMarkdownWhenCopyingIsEnabled() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let source = rootURL.appendingPathComponent("image.png")
        try Data("png".utf8).write(to: source)
        let viewModel = ScratchpadNotesViewModel(
            store: store,
            copyDraggedFilesToScratchpad: { true }
        )
        try viewModel.load()

        try viewModel.insertAttachment(
            from: source,
            isImage: true,
            now: Date(timeIntervalSince1970: 20)
        )
        try viewModel.flushPendingSave()

        XCTAssertEqual(viewModel.selectedNote?.body, "![image.png](attachments/image.png)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.noteDirectoryURL(forNoteID: note.id).appendingPathComponent("attachments/image.png").path))
    }

    @MainActor
    func testInsertAttachmentUsesAbsoluteFilePathWhenCopyingIsDisabled() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        try store.createNote(now: Date(timeIntervalSince1970: 10))
        let source = rootURL.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: source)
        let viewModel = ScratchpadNotesViewModel(
            store: store,
            copyDraggedFilesToScratchpad: { false }
        )
        try viewModel.load()

        try viewModel.insertAttachment(
            from: source,
            isImage: false,
            now: Date(timeIntervalSince1970: 20)
        )
        try viewModel.flushPendingSave()

        XCTAssertEqual(viewModel.selectedNote?.body, "[document.pdf](\(source.path))")
    }

    @discardableResult
    private func makeNote(store: ScratchpadStore, body: String, now: TimeInterval) throws -> ScratchpadNote {
        var note = try store.createNote(now: Date(timeIntervalSince1970: now))
        note.body = body
        return try store.saveNote(note, now: Date(timeIntervalSince1970: now))
    }
}
