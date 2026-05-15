import XCTest
@testable import NotchPilotKit

final class KnownAppTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let original = KnownApp(
            bundleIdentifier: "com.tencent.xinWeChat",
            displayName: "WeChat",
            iconCachePath: "/tmp/icon.png",
            discoverySource: .notificationArrival
        )

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(KnownApp.self, from: data)

        XCTAssertEqual(restored, original)
    }

    func testDecodesLegacyJSONAsDatabasePreload() throws {
        let data = try XCTUnwrap("""
        {
          "bundleIdentifier": "com.legacy.app",
          "displayName": "Legacy",
          "iconCachePath": null
        }
        """.data(using: .utf8))

        let restored = try JSONDecoder().decode(KnownApp.self, from: data)

        XCTAssertEqual(restored.discoverySource, .databasePreload)
    }

    func testIsEquatable() {
        let a = KnownApp(bundleIdentifier: "com.tencent.xinWeChat", displayName: "WeChat", iconCachePath: nil)
        let b = KnownApp(bundleIdentifier: "com.tencent.xinWeChat", displayName: "WeChat", iconCachePath: nil)
        XCTAssertEqual(a, b)
    }
}
