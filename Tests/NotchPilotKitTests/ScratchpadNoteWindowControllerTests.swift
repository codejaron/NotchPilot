import AppKit
import SwiftUI
import XCTest
@testable import NotchPilotKit

final class ScratchpadNoteWindowControllerTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScratchpadNoteWindowControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
    }

    @MainActor
    func testNoteWindowUsesStandardResizableMacWindowChrome() {
        let window = ScratchpadNoteWindowController.makeWindow(rootView: Text("Note"), title: "Note")

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.backgroundColor, .black)
    }

    @MainActor
    func testShowingSameNoteFocusesExistingWindow() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote()
        let controller = ScratchpadNoteWindowController()

        let first = try controller.show(noteID: note.id, store: store)
        let second = try controller.show(noteID: note.id, store: store)

        XCTAssertTrue(first === second)
        XCTAssertEqual(controller.openWindowCount, 1)

        first.close()
    }

    @MainActor
    func testDifferentNotesCanHaveSeparateWindows() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let firstNote = try store.createNote()
        let secondNote = try store.createNote()
        let controller = ScratchpadNoteWindowController()

        let firstWindow = try controller.show(noteID: firstNote.id, store: store)
        let secondWindow = try controller.show(noteID: secondNote.id, store: store)

        XCTAssertFalse(firstWindow === secondWindow)
        XCTAssertEqual(controller.openWindowCount, 2)

        firstWindow.close()
        secondWindow.close()
    }

    @MainActor
    func testFlushPendingSavesWritesStandaloneWindowDrafts() throws {
        let store = ScratchpadStore(rootURL: rootURL)
        let note = try store.createNote(now: Date(timeIntervalSince1970: 10))
        let controller = ScratchpadNoteWindowController()
        let window = try controller.show(noteID: note.id, store: store)
        let viewModel = try XCTUnwrap(controller.viewModel(noteID: note.id))

        try viewModel.updateSelectedBody("# Window Draft", now: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(try store.loadNote(id: note.id)?.body, "")

        controller.flushPendingSaves()

        XCTAssertEqual(try store.loadNote(id: note.id)?.body, "# Window Draft")
        window.close()
    }
}
