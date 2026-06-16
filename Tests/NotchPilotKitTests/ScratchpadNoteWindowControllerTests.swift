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
    func testNoteWindowUsesTransparentFullSizeResizableMacWindowChrome() throws {
        let window = ScratchpadNoteWindowController.makeWindow(rootView: Text("Note"), title: "Note")

        XCTAssertEqual(window.frame.size, NSSize(width: 620, height: 460))
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertTrue(window is ScratchpadNoteWindowFullscreenPanel)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
        XCTAssertFalse((window as? NSPanel)?.isFloatingPanel ?? true)
        XCTAssertTrue(window.contentView is ScratchpadNoteWindowFullSizeContentHosting)
        XCTAssertFalse(window.isOpaque)
        let backgroundAlpha = try XCTUnwrap(window.backgroundColor?.alphaComponent)
        XCTAssertGreaterThan(backgroundAlpha, 0.5)
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
    }

    @MainActor
    func testDefaultNoteWindowFrameCentersInVisibleScreen() {
        let frame = ScratchpadNoteWindowController.defaultWindowFrame(
            in: NSRect(x: 100, y: 50, width: 1440, height: 900)
        )

        XCTAssertEqual(frame.size, NSSize(width: 620, height: 460))
        XCTAssertEqual(frame.origin.x, 510)
        XCTAssertEqual(frame.origin.y, 270)
    }

    @MainActor
    func testApplyingPinnedStateUsesFullscreenAuxiliaryPanelAcrossAppSpaces() {
        let window = ScratchpadNoteWindowController.makeWindow(rootView: Text("Note"), title: "Note")

        ScratchpadNoteWindowController.applyPinnedState(true, to: window)

        XCTAssertEqual(window.level, .screenSaver)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue((window as? NSPanel)?.isFloatingPanel ?? false)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(window.collectionBehavior.contains(.transient))
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
    }

    @MainActor
    func testApplyingUnpinnedStateRestoresNormalSpaceScopedWindow() {
        let window = ScratchpadNoteWindowController.makeWindow(rootView: Text("Note"), title: "Note")
        ScratchpadNoteWindowController.applyPinnedState(true, to: window)

        ScratchpadNoteWindowController.applyPinnedState(false, to: window)

        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse((window as? NSPanel)?.isFloatingPanel ?? true)
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
        XCTAssertFalse(window.collectionBehavior.contains(.transient))
        XCTAssertFalse(window.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(window.collectionBehavior.contains(.managed))
        XCTAssertTrue(window.collectionBehavior.contains(.participatesInCycle))
    }

    @MainActor
    func testStandaloneWindowChromeUsesCompactCenteredTitleBarMetrics() {
        XCTAssertEqual(ScratchpadStandaloneWindowChromeMetrics.titleBarHeight, 32)
        XCTAssertGreaterThanOrEqual(
            ScratchpadStandaloneWindowChromeMetrics.titleHorizontalPadding,
            ScratchpadStandaloneWindowChromeMetrics.trailingControlWidth
        )
        XCTAssertLessThanOrEqual(ScratchpadStandaloneWindowChromeMetrics.iconButtonSize, 28)
        XCTAssertLessThanOrEqual(ScratchpadStandaloneWindowChromeMetrics.overflowButtonWidth, 36)
        XCTAssertGreaterThanOrEqual(ScratchpadStandaloneWindowChromeMetrics.inactiveIconOpacity, 0.68)
        XCTAssertTrue(ScratchpadStandaloneWindowChromeMetrics.usesAppKitOverflowMenu)
        XCTAssertFalse(ScratchpadStandaloneWindowChromeMetrics.titleTextStartsRename)
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
