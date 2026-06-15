import AppKit
import XCTest
@testable import NotchPilotKit

final class NotchGlobalDropStripTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        suiteName = "NotchGlobalDropStripTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempHomeURL)
        defaults = nil
        suiteName = nil
        tempHomeURL = nil
    }

    func testDropStripStateBuildsHoveringPromptWithFileCount() {
        let state = NotchGlobalDropStripState.hovering(fileCount: 3)

        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.fileCount, 3)
        XCTAssertEqual(state.message(language: .zhHans), "拖到这里添加到最近 note")
        XCTAssertEqual(state.accessoryText(language: .english), "3 files")
    }

    func testDropStripStateBuildsDisabledPrompt() {
        let state = NotchGlobalDropStripState.rejected(reason: .notesDisabled)

        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.fileCount, 0)
        XCTAssertEqual(state.message(language: .zhHans), "启用 Notes 后可添加文件")
        XCTAssertNil(state.accessoryText(language: .english))
    }

    func testDropStripStateBuildsUnsupportedPrompt() {
        let state = NotchGlobalDropStripState.rejected(reason: .unsupportedDrag)

        XCTAssertEqual(state.message(language: .zhHans), "只支持常见文件或图片")
        XCTAssertEqual(state.message(language: .english), "Common files or images only")
    }

    func testDropStripHeightOnlyContributesWhenVisible() {
        XCTAssertEqual(NotchExpandedLayout.dropStripHeight(for: .inactive), 0)
        XCTAssertEqual(
            NotchExpandedLayout.dropStripHeight(for: .hovering(fileCount: 1)),
            NotchExpandedLayout.globalDropStripHeight
        )
    }

    func testDragPasteboardReaderCountsSupportedFileURLs() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let fileURL = tempHomeURL.appendingPathComponent("dragged.pdf")
        try Data("pdf".utf8).write(to: fileURL)
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))
        let reader = NotchGlobalDragPasteboardReader(pasteboard: pasteboard)

        XCTAssertEqual(reader.fileURLCount(), 1)
    }

    func testDragPasteboardReaderIgnoresDirectoriesAndUnsupportedFiles() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let folderURL = tempHomeURL.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let appBundleURL = tempHomeURL.appendingPathComponent("Finder.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appBundleURL, withIntermediateDirectories: true)
        let unsupportedURL = tempHomeURL.appendingPathComponent("binary.bin")
        try Data("bin".utf8).write(to: unsupportedURL)
        XCTAssertTrue(pasteboard.writeObjects([folderURL as NSURL, appBundleURL as NSURL, unsupportedURL as NSURL]))
        let reader = NotchGlobalDragPasteboardReader(pasteboard: pasteboard)

        XCTAssertEqual(reader.fileURLCount(), 0)
    }

    func testDragPasteboardReaderAllowsSupportedDocumentPackages() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let packageURL = tempHomeURL.appendingPathComponent("Presentation.key", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        XCTAssertTrue(pasteboard.writeObjects([packageURL as NSURL]))
        let reader = NotchGlobalDragPasteboardReader(pasteboard: pasteboard)

        XCTAssertEqual(reader.fileURLCount(), 1)
    }

    @MainActor
    func testGlobalDragReducerShowsStripWhileFileDragIsInProgress() throws {
        let settingsStore = makeSettingsStore()
        let plugin = NotesPlugin(
            settingsStore: settingsStore,
            store: ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
        )
        let handler = NotchGlobalDropHandler(notesPlugin: { plugin }, selectNotes: {})

        let state = NotchGlobalDragReducer.state(
            eventType: .leftMouseDragged,
            fileURLCount: 2,
            currentState: .inactive,
            handler: handler
        )

        XCTAssertEqual(state, .hovering(fileCount: 2))
    }

    @MainActor
    func testGlobalDragReducerClearsPreviewOnMouseUp() throws {
        let handler = NotchGlobalDropHandler(notesPlugin: { nil }, selectNotes: {})

        let state = NotchGlobalDragReducer.state(
            eventType: .leftMouseUp,
            fileURLCount: 0,
            currentState: .hovering(fileCount: 1),
            handler: handler
        )

        XCTAssertEqual(state, .inactive)
    }

    @MainActor
    func testDropHandlerRejectsWhenNotesPluginIsDisabled() throws {
        let settingsStore = makeSettingsStore()
        settingsStore.notesEnabled = false
        let plugin = NotesPlugin(
            settingsStore: settingsStore,
            store: ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
        )
        var didSelectNotes = false
        let handler = NotchGlobalDropHandler(
            notesPlugin: { plugin },
            selectNotes: { didSelectNotes = true }
        )
        let source = tempHomeURL.appendingPathComponent("file.pdf")
        try Data("pdf".utf8).write(to: source)

        let state = handler.performDrop(urls: [source])

        XCTAssertEqual(state, .rejected(reason: .notesDisabled))
        XCTAssertFalse(didSelectNotes)
    }

    @MainActor
    func testDropHandlerIngestsSupportedFilesAndSelectsNotesWithoutOpening() throws {
        let scratchpadStore = ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
        let plugin = NotesPlugin(settingsStore: makeSettingsStore(), store: scratchpadStore)
        let source = tempHomeURL.appendingPathComponent("file.pdf")
        try Data("pdf".utf8).write(to: source)
        var didSelectNotes = false
        let handler = NotchGlobalDropHandler(
            notesPlugin: { plugin },
            selectNotes: { didSelectNotes = true }
        )

        let state = handler.performDrop(urls: [source])

        XCTAssertEqual(state, .accepted(fileCount: 1))
        XCTAssertTrue(didSelectNotes)
        XCTAssertEqual(try scratchpadStore.loadIndex().notes.count, 1)
    }

    @MainActor
    func testDropHandlerRejectsUnsupportedDirectoriesWithoutSelectingNotes() throws {
        let scratchpadStore = ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
        let plugin = NotesPlugin(settingsStore: makeSettingsStore(), store: scratchpadStore)
        let folderURL = tempHomeURL.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var didSelectNotes = false
        let handler = NotchGlobalDropHandler(
            notesPlugin: { plugin },
            selectNotes: { didSelectNotes = true }
        )

        let state = handler.performDrop(urls: [folderURL])

        XCTAssertEqual(state, .rejected(reason: .unsupportedDrag))
        XCTAssertFalse(didSelectNotes)
        XCTAssertEqual(try scratchpadStore.loadIndex().notes.count, 0)
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(defaults: defaults, fileManager: .default, homeDirectoryURL: tempHomeURL)
    }
}
