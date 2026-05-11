import XCTest
@testable import NotchPilotKit

final class NotificationDatabaseLocatorTests: XCTestCase {
    private final class FakeFM: NotificationDatabaseLocatorFileSystem {
        var existing: Set<String> = []
        func fileExists(atPath path: String) -> Bool { existing.contains(path) }
    }

    func testPrefersModernGroupContainerPath() {
        let fm = FakeFM()
        let home = URL(fileURLWithPath: "/Users/test")
        let modern = "/Users/test/Library/Group Containers/group.com.apple.usernoted/db2/db"
        let legacy = "/Users/test/Library/Application Support/NotificationCenter/db2/db"
        fm.existing = [modern, legacy]

        let locator = NotificationDatabaseLocator(fileSystem: fm, homeDirectoryURL: home)
        XCTAssertEqual(locator.locateDatabase(), URL(fileURLWithPath: modern))
    }

    func testFallsBackToLegacyPath() {
        let fm = FakeFM()
        let home = URL(fileURLWithPath: "/Users/test")
        let legacy = "/Users/test/Library/Application Support/NotificationCenter/db2/db"
        fm.existing = [legacy]

        let locator = NotificationDatabaseLocator(fileSystem: fm, homeDirectoryURL: home)
        XCTAssertEqual(locator.locateDatabase(), URL(fileURLWithPath: legacy))
    }

    func testReturnsNilWhenNothingExists() {
        let fm = FakeFM()
        let locator = NotificationDatabaseLocator(fileSystem: fm, homeDirectoryURL: URL(fileURLWithPath: "/Users/test"))
        XCTAssertNil(locator.locateDatabase())
    }
}
