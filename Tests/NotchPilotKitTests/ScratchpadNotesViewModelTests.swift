import AppKit
import SwiftUI
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

        XCTAssertEqual(reloaded.title, "Fresh Ti")
        XCTAssertEqual(reloaded.body, "# Fresh Title\nBody")
        XCTAssertEqual(viewModel.selectedNote?.title, "Fresh Ti")
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

    @MainActor
    func testRootViewSyncsEditorWhenSelectedNoteBodyChangesExternally() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        try store.createNote(now: Date(timeIntervalSince1970: 10))
        let source = rootURL.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: source)
        let viewModel = ScratchpadNotesViewModel(
            store: store,
            copyDraggedFilesToScratchpad: { false }
        )
        let hostingView = NSHostingView(rootView: ScratchpadNotesRootView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        let textView = try XCTUnwrap(findMarkdownTextView(in: hostingView))

        try viewModel.insertAttachment(
            from: source,
            isImage: false,
            now: Date(timeIntervalSince1970: 20)
        )
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(textView.string, "[document.pdf](\(source.path))")
    }

    @MainActor
    func testMarkdownTextViewRoutesFileDropsToAttachmentHandler() throws {
        let source = rootURL.appendingPathComponent("image.gif")
        try Data("gif".utf8).write(to: source)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScratchpadTextViewDrop.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([source as NSURL])
        let draggingInfo = ScratchpadTestDraggingInfo(pasteboard: pasteboard)
        let textView = ScratchpadMarkdownTextView()
        textView.string = "hello"
        var droppedURLs: [URL] = []
        textView.onDroppedFiles = { droppedURLs = $0 }

        XCTAssertEqual(textView.draggingEntered(draggingInfo), .copy)
        XCTAssertTrue(textView.performDragOperation(draggingInfo))

        XCTAssertEqual(droppedURLs, [source])
        XCTAssertEqual(textView.string, "hello")
    }

    @discardableResult
    private func makeNote(store: ScratchpadStore, body: String, now: TimeInterval) throws -> ScratchpadNote {
        var note = try store.createNote(now: Date(timeIntervalSince1970: now))
        note.body = body
        return try store.saveNote(note, now: Date(timeIntervalSince1970: now))
    }

    @MainActor
    private func findMarkdownTextView(in view: NSView) -> ScratchpadMarkdownTextView? {
        if let textView = view as? ScratchpadMarkdownTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findMarkdownTextView(in: subview) {
                return textView
            }
        }

        return nil
    }
}

@MainActor
private final class ScratchpadTestDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.draggingPasteboard = pasteboard
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
        nil
    }

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}
