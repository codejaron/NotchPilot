import AppKit
import XCTest
@testable import NotchPilotKit

final class NotificationAppDirectoryTests: XCTestCase {
    private final class StubWorkspace: NotificationAppDirectoryWorkspace {
        var lookups: [String: (url: URL, name: String)] = [:]
        func appURL(forBundleIdentifier id: String) -> URL? { lookups[id]?.url }
        func appName(forBundleIdentifier id: String) -> String? { lookups[id]?.name }
    }

    @MainActor
    func testReturnsResolvedAppMeta() {
        let stub = StubWorkspace()
        stub.lookups["com.tencent.xinWeChat"] = (
            URL(fileURLWithPath: "/Applications/WeChat.app"),
            "WeChat"
        )
        let dir = NotificationAppDirectory(workspace: stub)

        let meta = dir.resolve(bundleIdentifier: "com.tencent.xinWeChat")
        XCTAssertEqual(meta?.displayName, "WeChat")
        XCTAssertEqual(meta?.bundleIdentifier, "com.tencent.xinWeChat")
    }

    @MainActor
    func testCachesLookups() {
        final class CountingStub: NotificationAppDirectoryWorkspace {
            var calls = 0
            func appURL(forBundleIdentifier id: String) -> URL? {
                calls += 1
                return URL(fileURLWithPath: "/Applications/X.app")
            }
            func appName(forBundleIdentifier id: String) -> String? { "X" }
        }
        let stub = CountingStub()
        let dir = NotificationAppDirectory(workspace: stub)
        _ = dir.resolve(bundleIdentifier: "x")
        _ = dir.resolve(bundleIdentifier: "x")
        XCTAssertEqual(stub.calls, 1)
    }

    @MainActor
    func testReturnsNilWhenWorkspaceUnknown() {
        let stub = StubWorkspace()
        let dir = NotificationAppDirectory(workspace: stub)
        XCTAssertNil(dir.resolve(bundleIdentifier: "com.unknown"))
    }
}
