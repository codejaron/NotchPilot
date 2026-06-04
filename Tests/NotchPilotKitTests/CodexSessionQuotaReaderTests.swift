import XCTest
@testable import NotchPilotKit

final class CodexSessionQuotaReaderTests: XCTestCase {
    private var tempHomeURL: URL!
    private let recentSessionNow = Date(timeIntervalSince1970: 1_780_488_000)

    override func setUpWithError() throws {
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHomeURL)
        tempHomeURL = nil
    }

    func testLatestTokenCountTimestampWinsAcrossSessionFiles() async throws {
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

        let now = recentSessionNow
        let reader = CodexSessionQuotaReader(
            homeDirectoryURL: tempHomeURL,
            nowProvider: { now }
        )
        let maybeSnapshot = await reader.latestSnapshot(collectedAt: Date(timeIntervalSince1970: 0))
        let snapshot = try XCTUnwrap(maybeSnapshot)

        XCTAssertEqual(snapshot.window(.fiveHour)?.remainingPercent, 75)
        XCTAssertEqual(snapshot.window(.sevenDay)?.remainingPercent, 90)
    }

    func testLatestTokenCountWithoutRateLimitsReturnsNil() async throws {
        try writeSessionLog(
            path: "2026/06/02/latest.jsonl",
            lines: [
                """
                {"timestamp":"2026-06-02T03:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400}}}
                """,
            ]
        )

        let now = recentSessionNow
        let reader = CodexSessionQuotaReader(
            homeDirectoryURL: tempHomeURL,
            nowProvider: { now }
        )

        let snapshot = await reader.latestSnapshot(collectedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(snapshot)
    }

    func testPreferredChangedSessionFileIsUsedBeforeDirectoryScan() async throws {
        try writeSessionLog(
            path: "2026/06/03/newer.jsonl",
            lines: [
                tokenCountLine(timestamp: "2026-06-03T03:00:00.000Z", primaryUsed: 80, secondaryUsed: 20),
            ]
        )
        let preferredURL = try writeSessionLog(
            path: "2026/06/01/changed.jsonl",
            lines: [
                tokenCountLine(timestamp: "2026-06-01T03:00:00.000Z", primaryUsed: 35, secondaryUsed: 10),
            ]
        )

        let now = recentSessionNow
        let reader = CodexSessionQuotaReader(
            homeDirectoryURL: tempHomeURL,
            nowProvider: { now }
        )
        let maybeSnapshot = await reader.latestSnapshot(
            collectedAt: Date(timeIntervalSince1970: 0),
            preferredFileURL: preferredURL
        )
        let snapshot = try XCTUnwrap(maybeSnapshot)

        XCTAssertEqual(snapshot.window(.fiveHour)?.remainingPercent, 65)
    }

    @discardableResult
    private func writeSessionLog(path: String, lines: [String]) throws -> URL {
        let url = tempHomeURL
            .appendingPathComponent(".codex/sessions", isDirectory: true)
            .appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func tokenCountLine(timestamp: String, primaryUsed: Int, secondaryUsed: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400}},"rate_limits":{"primary":{"used_percent":\(primaryUsed),"window_minutes":300,"resets_at":1780302427},"secondary":{"used_percent":\(secondaryUsed),"window_minutes":10080,"resets_at":1780889227},"plan_type":"plus"}}
        """
    }
}
