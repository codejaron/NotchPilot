import AppKit
import XCTest
@testable import NotchPilotKit

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testClosingLastWindowDoesNotTerminateApplication() {
        let delegate = NotchPilotAppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testInitialPluginRegistrationUsesSingleAIPlugin() {
        let delegate = NotchPilotAppDelegate()

        XCTAssertEqual(delegate.registeredPluginIDsForTesting, ["ai"])
    }
}
