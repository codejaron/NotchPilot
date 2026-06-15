import CoreGraphics
import SwiftUI
import XCTest
@testable import NotchPilotKit

final class NotesPluginTests: XCTestCase {
    private static let context = NotchContext(
        screenID: "test-screen",
        notchState: .open,
        notchGeometry: NotchGeometry(
            compactSize: CGSize(width: 185, height: 32),
            expandedSize: CGSize(width: 720, height: 240)
        ),
        isPrimaryScreen: true
    )

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        suiteName = "NotesPluginTests.\(UUID().uuidString)"
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

    @MainActor
    func testPluginMetadataMatchesNotesEntryAndDoesNotPreview() {
        let plugin = NotesPlugin(settingsStore: makeSettingsStore())

        XCTAssertEqual(plugin.id, "notes")
        XCTAssertEqual(plugin.title, "Notes")
        XCTAssertEqual(plugin.iconSystemName, "note.text")
        XCTAssertEqual(plugin.dockOrder, 130)
        XCTAssertTrue(plugin.isEnabled)
        XCTAssertNil(plugin.previewPriority)
        XCTAssertNil(plugin.preview(context: Self.context))
    }

    @MainActor
    func testPluginReflectsNotesAvailabilitySetting() {
        let store = makeSettingsStore()
        store.notesEnabled = false
        let plugin = NotesPlugin(settingsStore: store)

        XCTAssertFalse(plugin.isEnabled)

        store.notesEnabled = true

        XCTAssertTrue(plugin.isEnabled)
    }

    @MainActor
    func testTogglePinnedNotchEmitsOppositePinnedState() {
        let plugin = NotesPlugin(settingsStore: makeSettingsStore())
        let bus = EventBus()
        var events: [NotchEvent] = []
        bus.subscribe { events.append($0) }
        plugin.activate(bus: bus)

        plugin.toggleNotchPin(isCurrentlyPinned: false, screenID: "test-screen")
        plugin.toggleNotchPin(isCurrentlyPinned: true, screenID: "test-screen")

        XCTAssertEqual(events, [
            .setOpenPinned(true, target: .screen(id: "test-screen")),
            .setOpenPinned(false, target: .screen(id: "test-screen")),
        ])
    }

    @MainActor
    func testIngestDroppedFilesCreatesNoteAndInsertsMarkdown() throws {
        let scratchpadStore = ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
        let plugin = NotesPlugin(settingsStore: makeSettingsStore(), store: scratchpadStore)
        let source = tempHomeURL.appendingPathComponent("image.png")
        try Data("png".utf8).write(to: source)

        let result = try plugin.ingestDroppedFiles(
            [source],
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        let note = try XCTUnwrap(scratchpadStore.loadNote(id: result.noteID))
        XCTAssertEqual(note.body, "![image.png](attachments/image.png)")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: scratchpadStore
                    .noteDirectoryURL(forNoteID: result.noteID)
                    .appendingPathComponent("attachments/image.png")
                    .path
            )
        )
    }

    @MainActor
    func testIngestDroppedFilesUsesRecentNoteAndReportsPartialFailures() throws {
        let scratchpadStore = ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
        _ = try scratchpadStore.createNote(now: Date(timeIntervalSince1970: 10))
        let recent = try scratchpadStore.createNote(now: Date(timeIntervalSince1970: 20))
        let plugin = NotesPlugin(settingsStore: makeSettingsStore(), store: scratchpadStore)
        let source = tempHomeURL.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: source)
        let missing = tempHomeURL.appendingPathComponent("missing.pdf")

        let result = try plugin.ingestDroppedFiles(
            [source, missing],
            now: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(result.noteID, recent.id)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(
            try scratchpadStore.loadNote(id: recent.id)?.body,
            "[document.pdf](attachments/document.pdf)"
        )
    }

    @MainActor
    func testDeactivateFlushesPendingNoteSave() throws {
        let scratchpadStore = ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
        let note = try scratchpadStore.createNote(now: Date(timeIntervalSince1970: 10))
        let plugin = NotesPlugin(settingsStore: makeSettingsStore(), store: scratchpadStore)
        try plugin.viewModel.load()

        try plugin.viewModel.updateSelectedBody("# Pending", now: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(try scratchpadStore.loadNote(id: note.id)?.body, "")

        plugin.deactivate()

        XCTAssertEqual(try scratchpadStore.loadNote(id: note.id)?.body, "# Pending")
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(defaults: defaults, fileManager: .default, homeDirectoryURL: tempHomeURL)
    }
}
