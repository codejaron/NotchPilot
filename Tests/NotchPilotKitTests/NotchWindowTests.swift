import CoreGraphics
import AppKit
import XCTest
@testable import NotchPilotKit

final class NotchWindowTests: XCTestCase {
    func testDefaultStyleMaskDoesNotRequestSystemHUDChrome() {
        let styleMask = NotchWindowStyle.defaultStyleMask

        XCTAssertTrue(styleMask.contains(.borderless))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(styleMask.contains(.utilityWindow))
        XCTAssertFalse(styleMask.contains(.hudWindow))
    }

    func testFrameRefreshPlanSkipsWindowUpdateWhenTargetFrameIsUnchanged() {
        let frame = CGRect(x: 100, y: 200, width: 520, height: 340)

        let plan = NotchWindowFrameRefreshPlan.resolve(currentFrame: frame, targetFrame: frame)

        XCTAssertFalse(plan.needsWindowFrameUpdate)
        XCTAssertEqual(plan.targetFrame, frame)
    }

    func testFrameRefreshPlanUpdatesWindowWhenTargetFrameChanges() {
        let currentFrame = CGRect(x: 100, y: 200, width: 520, height: 340)
        let targetFrame = CGRect(x: 120, y: 210, width: 600, height: 340)

        let plan = NotchWindowFrameRefreshPlan.resolve(currentFrame: currentFrame, targetFrame: targetFrame)

        XCTAssertTrue(plan.needsWindowFrameUpdate)
        XCTAssertEqual(plan.targetFrame, targetFrame)
    }

    func testInteractionFrameCacheReusesFrameUntilInvalidated() {
        var cache = NotchWindowInteractionFrameCache()
        var resolveCount = 0
        let first = cache.frame {
            resolveCount += 1
            return CGRect(x: 10, y: 20, width: 30, height: 40)
        }
        let second = cache.frame {
            resolveCount += 1
            return CGRect(x: 50, y: 60, width: 70, height: 80)
        }

        XCTAssertEqual(first, CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(second, first)
        XCTAssertEqual(resolveCount, 1)

        cache.invalidate()
        let third = cache.frame {
            resolveCount += 1
            return CGRect(x: 50, y: 60, width: 70, height: 80)
        }

        XCTAssertEqual(third, CGRect(x: 50, y: 60, width: 70, height: 80))
        XCTAssertEqual(resolveCount, 2)
    }

    func testMouseEventsStayIgnoredWhenClosedEvenWhileHoveringNotch() {
        XCTAssertTrue(
            NotchWindowMouseEventPolicy.ignoresMouseEvents(
                notchState: .idleClosed,
                isHoveringInteractionFrame: true,
                isGlobalFileDragActive: false,
                isGlobalDropStripVisible: false
            )
        )
        XCTAssertTrue(
            NotchWindowMouseEventPolicy.ignoresMouseEvents(
                notchState: .previewClosed,
                isHoveringInteractionFrame: true,
                isGlobalFileDragActive: false,
                isGlobalDropStripVisible: false
            )
        )
        XCTAssertFalse(
            NotchWindowMouseEventPolicy.ignoresMouseEvents(
                notchState: .open,
                isHoveringInteractionFrame: true,
                isGlobalFileDragActive: false,
                isGlobalDropStripVisible: false
            )
        )
        XCTAssertTrue(
            NotchWindowMouseEventPolicy.ignoresMouseEvents(
                notchState: .open,
                isHoveringInteractionFrame: false,
                isGlobalFileDragActive: false,
                isGlobalDropStripVisible: false
            )
        )
        XCTAssertFalse(
            NotchWindowMouseEventPolicy.ignoresMouseEvents(
                notchState: .idleClosed,
                isHoveringInteractionFrame: true,
                isGlobalFileDragActive: true,
                isGlobalDropStripVisible: false
            )
        )
        XCTAssertFalse(
            NotchWindowMouseEventPolicy.ignoresMouseEvents(
                notchState: .idleClosed,
                isHoveringInteractionFrame: true,
                isGlobalFileDragActive: false,
                isGlobalDropStripVisible: true
            )
        )
    }

    @MainActor
    func testWindowCloseDoesNotReleaseARCManagedInstance() {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )
        let pluginManager = PluginManager()
        let window = NotchWindow(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: NotchWindowTestMouseActivityMonitor()
        )

        XCTAssertFalse(window.isReleasedWhenClosed)

        window.close()
    }

    @MainActor
    func testWindowRemainsAvailableToScreenCaptureAndWindowSharing() {
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )
        let pluginManager = PluginManager()
        let window = NotchWindow(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: NotchWindowTestMouseActivityMonitor()
        )
        defer { window.close() }

        XCTAssertNotEqual(window.sharingType, .none)
    }

    @MainActor
    func testGlobalFileDragShowsDropStripBeforePointerReachesNotch() throws {
        let tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchWindowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHomeURL) }

        let suiteName = "NotchWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(defaults: defaults, fileManager: .default, homeDirectoryURL: tempHomeURL)
        let pluginManager = PluginManager()
        pluginManager.register(
            NotesPlugin(
                settingsStore: settingsStore,
                store: ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
            )
        )
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )
        session.activePluginID = "other"
        let monitor = NotchWindowTestMouseActivityMonitor()
        let dragReader = NotchWindowTestGlobalDragReader(count: 0, changeCount: 10)
        let window = NotchWindow(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: monitor,
            globalDragPasteboardReader: dragReader
        )
        defer { window.close() }
        dragReader.snapshotValue = NotchGlobalDragPasteboardSnapshot(changeCount: 11, supportedFileURLCount: 1)

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )

        _ = monitor.emit(scope: .global, event: event)

        XCTAssertEqual(session.globalDropStripState, .hovering(fileCount: 1))
        XCTAssertEqual(session.activePluginID, SettingsPluginID.notes.rawValue)
        XCTAssertFalse(window.ignoresMouseEvents)
    }

    @MainActor
    func testGlobalFileDragKeepsDropStripVisibleForRepeatedFramesWithSamePasteboardChangeCount() throws {
        let tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchWindowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHomeURL) }

        let suiteName = "NotchWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(defaults: defaults, fileManager: .default, homeDirectoryURL: tempHomeURL)
        let pluginManager = PluginManager()
        pluginManager.register(
            NotesPlugin(
                settingsStore: settingsStore,
                store: ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
            )
        )
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )
        let monitor = NotchWindowTestMouseActivityMonitor()
        let dragReader = NotchWindowTestGlobalDragReader(count: 0, changeCount: 40)
        let window = NotchWindow(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: monitor,
            globalDragPasteboardReader: dragReader
        )
        defer { window.close() }
        dragReader.snapshotValue = NotchGlobalDragPasteboardSnapshot(changeCount: 41, supportedFileURLCount: 2)

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )

        _ = monitor.emit(scope: .global, event: event)
        _ = monitor.emit(scope: .global, event: event)

        XCTAssertEqual(session.globalDropStripState, .hovering(fileCount: 2))
    }

    @MainActor
    func testGlobalMouseDragIgnoresStaleFileDragPasteboard() throws {
        let tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchWindowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHomeURL) }

        let suiteName = "NotchWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(defaults: defaults, fileManager: .default, homeDirectoryURL: tempHomeURL)
        let pluginManager = PluginManager()
        pluginManager.register(
            NotesPlugin(
                settingsStore: settingsStore,
                store: ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
            )
        )
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )
        let monitor = NotchWindowTestMouseActivityMonitor()
        let dragReader = NotchWindowTestGlobalDragReader(count: 1, changeCount: 20)
        let window = NotchWindow(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: monitor,
            globalDragPasteboardReader: dragReader
        )
        defer { window.close() }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )

        _ = monitor.emit(scope: .global, event: event)

        XCTAssertEqual(session.globalDropStripState, .inactive)
    }

    @MainActor
    func testGlobalMouseDragIgnoresFilePasteboardAfterDragEnded() throws {
        let tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchWindowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHomeURL) }

        let suiteName = "NotchWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(defaults: defaults, fileManager: .default, homeDirectoryURL: tempHomeURL)
        let pluginManager = PluginManager()
        pluginManager.register(
            NotesPlugin(
                settingsStore: settingsStore,
                store: ScratchpadStore(rootURL: tempHomeURL.appendingPathComponent("Scratchpad", isDirectory: true))
            )
        )
        let session = ScreenSessionModel(
            descriptor: ScreenDescriptor(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isPrimary: true
            )
        )
        let monitor = NotchWindowTestMouseActivityMonitor()
        let dragReader = NotchWindowTestGlobalDragReader(count: 0, changeCount: 30)
        let window = NotchWindow(
            session: session,
            pluginManager: pluginManager,
            mouseActivityMonitor: monitor,
            globalDragPasteboardReader: dragReader
        )
        defer { window.close() }
        let dragEvent = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
        let mouseUpEvent = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )

        dragReader.snapshotValue = NotchGlobalDragPasteboardSnapshot(changeCount: 31, supportedFileURLCount: 1)
        _ = monitor.emit(scope: .global, event: dragEvent)
        _ = monitor.emit(scope: .global, event: mouseUpEvent)
        _ = monitor.emit(scope: .global, event: dragEvent)

        XCTAssertEqual(session.globalDropStripState, .inactive)
        XCTAssertTrue(window.ignoresMouseEvents)
    }
}

@MainActor
private final class NotchWindowTestMouseActivityMonitor: MouseActivityMonitoring {
    private var handler: (@MainActor (MouseActivityEvent) -> MouseActivityHandlingResult)?

    func addSubscriber(
        _ handler: @escaping @MainActor (MouseActivityEvent) -> MouseActivityHandlingResult
    ) -> UUID {
        self.handler = handler
        return UUID()
    }

    func removeSubscriber(_ token: UUID) {
        handler = nil
    }

    func emit(scope: MouseActivityScope, event: NSEvent) -> MouseActivityHandlingResult? {
        handler?(MouseActivityEvent(scope: scope, event: event))
    }
}

private final class NotchWindowTestGlobalDragReader: NotchGlobalDragPasteboardReading {
    var snapshotValue: NotchGlobalDragPasteboardSnapshot

    init(count: Int, changeCount: Int) {
        self.snapshotValue = NotchGlobalDragPasteboardSnapshot(
            changeCount: changeCount,
            supportedFileURLCount: count
        )
    }

    func snapshot() -> NotchGlobalDragPasteboardSnapshot {
        snapshotValue
    }
}
