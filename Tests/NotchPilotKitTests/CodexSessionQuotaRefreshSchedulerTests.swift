import CoreServices
import XCTest
@testable import NotchPilotKit

final class CodexSessionQuotaRefreshSchedulerTests: XCTestCase {
    func testCFEventPathsSelectsFirstJSONLPath() {
        let eventPaths = [
            "/Users/test/.codex/sessions/readme.txt",
            "/Users/test/.codex/sessions/2026/session.jsonl",
            "/Users/test/.codex/sessions/other.jsonl",
        ] as CFArray

        let fileURL = CodexSessionQuotaRefreshScheduler.changedSessionFileURL(fromCFEventPaths: eventPaths)

        XCTAssertEqual(fileURL?.path, "/Users/test/.codex/sessions/2026/session.jsonl")
    }
}
