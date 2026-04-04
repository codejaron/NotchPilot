import XCTest
@testable import NotchPilotKit

final class HookResponseEncoderTests: XCTestCase {
    func testClaudePersistentApprovalAddsPersistFlag() throws {
        let data = try HookResponseEncoder().encode(
            decision: .persistAllowRule,
            for: .claude
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"decision\":\"allow\""))
        XCTAssertTrue(json.contains("\"persist\":true"))
    }

    func testCodexDenyUsesActionKey() throws {
        let data = try HookResponseEncoder().encode(
            decision: .denyOnce,
            for: .codex
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(json, #"{"action":"deny"}"#)
    }
}
