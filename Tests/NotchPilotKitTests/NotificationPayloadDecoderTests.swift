import XCTest
@testable import NotchPilotKit

final class NotificationPayloadDecoderTests: XCTestCase {
    private let decoder = NotificationPayloadDecoder()

    // MARK: - Helpers: build synthetic payloads matching the real DB shapes

    /// Shape A: NSKeyedArchiver-wrapped dict.
    private func archivedPayload(_ dict: [String: Any]) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false)
    }

    /// Shape B: plain binary plist (no archiver wrapping).
    private func plainPayload(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    // MARK: - Happy paths

    func testDecodesArchivedShapeWithReqSubdict() throws {
        let dict: [String: Any] = [
            "app": "com.tencent.xinWeChat",
            "req": [
                "titl": "张三",
                "subt": "群聊",
                "body": "明天下午开会"
            ] as [String: Any]
        ]
        let data = try archivedPayload(dict)
        let result = try XCTUnwrap(decoder.decode(payload: data))

        XCTAssertEqual(result.bundleIdentifier, "com.tencent.xinWeChat")
        XCTAssertEqual(result.title, "张三")
        XCTAssertEqual(result.subtitle, "群聊")
        XCTAssertEqual(result.body, "明天下午开会")
    }

    func testDecodesPlainShapeWithModernKeys() throws {
        let dict: [String: Any] = [
            "appBundleIdentifier": "com.apple.Mail",
            "request": [
                "title": "Pull Request Review",
                "subtitle": "Repo / Branch",
                "body": "Please review #1234"
            ] as [String: Any]
        ]
        let data = try plainPayload(dict)
        let result = try XCTUnwrap(decoder.decode(payload: data))

        XCTAssertEqual(result.bundleIdentifier, "com.apple.Mail")
        XCTAssertEqual(result.title, "Pull Request Review")
        XCTAssertEqual(result.subtitle, "Repo / Branch")
        XCTAssertEqual(result.body, "Please review #1234")
    }

    func testDecodesFieldsFromRootDictWhenNoReqSubdict() throws {
        // Some apps flatten the request fields onto the root.
        let dict: [String: Any] = [
            "app": "com.apple.iCal",
            "title": "Meeting in 5 minutes",
            "body": "Project sync"
        ]
        let data = try plainPayload(dict)
        let result = try XCTUnwrap(decoder.decode(payload: data))

        XCTAssertEqual(result.bundleIdentifier, "com.apple.iCal")
        XCTAssertEqual(result.title, "Meeting in 5 minutes")
        XCTAssertEqual(result.body, "Project sync")
        XCTAssertNil(result.subtitle)
    }

    func testDecodesArchivedPayloadWithMissingOptionalFields() throws {
        // Only bundle id + body; no title/subtitle.
        let dict: [String: Any] = [
            "app": "com.example.test",
            "req": ["body": "Just a body"] as [String: Any]
        ]
        let data = try archivedPayload(dict)
        let result = try XCTUnwrap(decoder.decode(payload: data))

        XCTAssertEqual(result.bundleIdentifier, "com.example.test")
        XCTAssertNil(result.title)
        XCTAssertNil(result.subtitle)
        XCTAssertEqual(result.body, "Just a body")
    }

    func testDecodesUsingInformativeTextFallback() throws {
        // Older payloads sometimes use `informativeText` instead of `body`.
        let dict: [String: Any] = [
            "app": "com.legacy.app",
            "title": "Hi",
            "informativeText": "Legacy body field"
        ]
        let data = try plainPayload(dict)
        let result = try XCTUnwrap(decoder.decode(payload: data))

        XCTAssertEqual(result.bundleIdentifier, "com.legacy.app")
        XCTAssertEqual(result.body, "Legacy body field")
    }

    // MARK: - Negative cases

    func testReturnsNilForEmptyData() {
        XCTAssertNil(decoder.decode(payload: Data()))
    }

    func testReturnsNilForGarbageData() {
        XCTAssertNil(decoder.decode(payload: Data([0xff, 0xfe, 0xfd, 0xfc])))
    }

    func testReturnsNilWhenBundleIDMissing() throws {
        // No `app` or `appBundleIdentifier` — undecodable.
        let dict: [String: Any] = [
            "req": ["body": "no app id"] as [String: Any]
        ]
        let data = try plainPayload(dict)
        XCTAssertNil(decoder.decode(payload: data))
    }
}
