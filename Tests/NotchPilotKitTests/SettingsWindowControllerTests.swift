import AppKit
import XCTest
@testable import NotchPilotKit

final class SettingsWindowControllerTests: XCTestCase {
    @MainActor
    func testSettingsWindowUsesStandardWindowDragging() {
        let window = SettingsWindowController.makeWindow(rootView: SettingsView(selectedPane: .general))

        XCTAssertFalse(window.isMovableByWindowBackground)
    }

    @MainActor
    func testSettingsWindowUsesFullSizeTransparentTitlebar() {
        let window = SettingsWindowController.makeWindow(rootView: SettingsView(selectedPane: .general))

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, NSWindow.TitleVisibility.hidden)
        XCTAssertEqual(window.toolbarStyle, NSWindow.ToolbarStyle.unifiedCompact)
    }
}
