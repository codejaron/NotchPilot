import XCTest
@testable import NotchPilotKit

final class ClaudeToolUseCorrelatorTests: XCTestCase {
    func testCorrelatesPermissionRequestWithPreviouslyObservedToolUseID() {
        var correlator = ClaudeToolUseCorrelator()

        correlator.observe(
            sessionID: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("swift test")]),
            toolUseID: "toolu-1"
        )

        let correlatedID = correlator.correlatedToolUseID(
            sessionID: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("swift test")])
        )

        XCTAssertEqual(correlatedID, "toolu-1")
    }

    func testCorrelationConsumesOnlyTheMatchingToolUseID() {
        var correlator = ClaudeToolUseCorrelator()

        correlator.observe(
            sessionID: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("swift test")]),
            toolUseID: "toolu-1"
        )

        XCTAssertEqual(
            correlator.correlatedToolUseID(
                sessionID: "session-1",
                toolName: "Bash",
                toolInput: .object(["command": .string("swift test")])
            ),
            "toolu-1"
        )
        XCTAssertNil(
            correlator.correlatedToolUseID(
                sessionID: "session-1",
                toolName: "Bash",
                toolInput: .object(["command": .string("swift test")])
            )
        )
    }

    func testClearsToolUseIDsForStoppedSessionOnly() {
        var correlator = ClaudeToolUseCorrelator()

        correlator.observe(
            sessionID: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("swift test")]),
            toolUseID: "toolu-1"
        )
        correlator.observe(
            sessionID: "session-2",
            toolName: "Bash",
            toolInput: .object(["command": .string("swift build")]),
            toolUseID: "toolu-2"
        )

        correlator.clear(sessionID: "session-1")

        XCTAssertNil(
            correlator.correlatedToolUseID(
                sessionID: "session-1",
                toolName: "Bash",
                toolInput: .object(["command": .string("swift test")])
            )
        )
        XCTAssertEqual(
            correlator.correlatedToolUseID(
                sessionID: "session-2",
                toolName: "Bash",
                toolInput: .object(["command": .string("swift build")])
            ),
            "toolu-2"
        )
    }
}
