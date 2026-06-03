import XCTest
@testable import NotchPilotKit

final class CodexSessionQuotaReaderTests: XCTestCase {
    private var tempHomeURL: URL!

    override func setUpWithError() throws {
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHomeURL)
        tempHomeURL = nil
    }

    func testLatestTokenCountTimestampWinsAcrossSessionFiles() throws {
        try writeSessionLog(
            path: "2026/06/01/older.jsonl",
            lines: [
                tokenCountLine(timestamp: "2026-06-01T03:00:00.000Z", primaryUsed: 80, secondaryUsed: 20),
            ]
        )
        try writeSessionLog(
            path: "2026/06/02/newer.jsonl",
            lines: [
                tokenCountLine(timestamp: "2026-06-02T03:00:00.000Z", primaryUsed: 25, secondaryUsed: 10),
            ]
        )

        let reader = CodexSessionQuotaReader(homeDirectoryURL: tempHomeURL)
        let snapshot = try XCTUnwrap(reader.latestSnapshot(collectedAt: Date(timeIntervalSince1970: 0)))

        XCTAssertEqual(snapshot.window(.fiveHour)?.remainingPercent, 75)
        XCTAssertEqual(snapshot.window(.sevenDay)?.remainingPercent, 90)
    }

    func testLatestTokenCountWithoutRateLimitsReturnsNil() throws {
        try writeSessionLog(
            path: "2026/06/02/latest.jsonl",
            lines: [
                """
                {"timestamp":"2026-06-02T03:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400}}}
                """,
            ]
        )

        let reader = CodexSessionQuotaReader(homeDirectoryURL: tempHomeURL)

        XCTAssertNil(reader.latestSnapshot(collectedAt: Date(timeIntervalSince1970: 0)))
    }

    private func writeSessionLog(path: String, lines: [String]) throws {
        let url = tempHomeURL
            .appendingPathComponent(".codex/sessions", isDirectory: true)
            .appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func tokenCountLine(timestamp: String, primaryUsed: Int, secondaryUsed: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400}},"rate_limits":{"primary":{"used_percent":\(primaryUsed),"window_minutes":300,"resets_at":1780302427},"secondary":{"used_percent":\(secondaryUsed),"window_minutes":10080,"resets_at":1780889227},"plan_type":"plus"}}
        """
    }
}
