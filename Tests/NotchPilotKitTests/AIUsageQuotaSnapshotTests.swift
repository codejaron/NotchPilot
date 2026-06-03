import XCTest
@testable import NotchPilotKit

final class AIUsageQuotaSnapshotTests: XCTestCase {
    func testQuotaHeaderPresentationBuildsProviderLevelInlineItems() {
        let presentation = AIUsageQuotaHeaderPresentation(
            snapshots: [
                AIUsageQuotaSnapshot(
                    host: .codex,
                    source: .codexSessionLog,
                    collectedAt: Date(timeIntervalSince1970: 0),
                    windows: [
                        AIUsageQuotaWindow(kind: .fiveHour, usedPercent: 47, resetsAt: nil, windowMinutes: 300),
                        AIUsageQuotaWindow(kind: .sevenDay, usedPercent: 27, resetsAt: nil, windowMinutes: 10_080),
                    ],
                    planType: "plus"
                ),
                AIUsageQuotaSnapshot(
                    host: .claude,
                    source: .claudeStatusLine,
                    collectedAt: Date(timeIntervalSince1970: 0),
                    windows: [
                        AIUsageQuotaWindow(kind: .fiveHour, usedPercent: 25, resetsAt: nil, windowMinutes: nil),
                        AIUsageQuotaWindow(kind: .sevenDay, usedPercent: 10, resetsAt: nil, windowMinutes: nil),
                    ],
                    planType: "max"
                ),
            ]
        )

        XCTAssertEqual(presentation.items.map(\.host), [.claude, .codex])
        XCTAssertEqual(presentation.items.map(\.accessibilityText), [
            "Claude 5h 75% 7d 90%",
            "Codex 5h 53% 7d 73%",
        ])
    }

    func testQuotaHeaderPresentationIgnoresSnapshotsWithoutQuotaWindows() {
        let presentation = AIUsageQuotaHeaderPresentation(
            snapshots: [
                AIUsageQuotaSnapshot(
                    host: .claude,
                    source: .claudeStatusLine,
                    collectedAt: Date(timeIntervalSince1970: 0),
                    windows: [],
                    planType: nil
                ),
            ]
        )

        XCTAssertTrue(presentation.items.isEmpty)
        XCTAssertFalse(presentation.shouldRender)
    }

    func testClaudeStatusLineParsesFiveHourAndSevenDayLimits() throws {
        let snapshot = try XCTUnwrap(
            AIUsageQuotaSnapshot.claudeStatusLine(
                rawJSON: """
                {
                  "notchpilot_event_name": "StatusLine",
                  "payload": {
                    "rate_limits": {
                      "plan_type": "max",
                      "five_hour": {
                        "used_percentage": 25,
                        "resets_at": "2026-06-02T12:00:00Z"
                      },
                      "seven_day": {
                        "used_percentage": 10,
                        "resets_at": "2026-06-08T12:00:00Z"
                      }
                    }
                  }
                }
                """,
                collectedAt: Date(timeIntervalSince1970: 0)
            )
        )

        XCTAssertEqual(snapshot.host, .claude)
        XCTAssertEqual(snapshot.planType, "max")
        XCTAssertEqual(snapshot.window(.fiveHour)?.remainingPercent, 75)
        XCTAssertEqual(snapshot.window(.sevenDay)?.remainingPercent, 90)
    }

    func testClaudeStatusLineWithoutRateLimitsReturnsNil() {
        XCTAssertNil(
            AIUsageQuotaSnapshot.claudeStatusLine(
                rawJSON: #"{"notchpilot_event_name":"StatusLine","payload":{"model":"relay"}}"#,
                collectedAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    func testCodexSessionLogParsesPrimaryAndSecondaryLimits() throws {
        let snapshot = try XCTUnwrap(
            AIUsageQuotaSnapshot.codexSessionLog(
                rawJSON: """
                {
                  "timestamp": "2026-06-01T03:27:10.944Z",
                  "type": "event_msg",
                  "payload": {
                    "type": "token_count",
                    "info": {
                      "model_context_window": 258400
                    }
                  },
                  "rate_limits": {
                    "primary": {
                      "used_percent": 20,
                      "window_minutes": 300,
                      "resets_at": 1780302427
                    },
                    "secondary": {
                      "used_percent": 40,
                      "window_minutes": 10080,
                      "resets_at": 1780889227
                    },
                    "plan_type": "plus"
                  }
                }
                """,
                collectedAt: Date(timeIntervalSince1970: 0)
            )
        )

        XCTAssertEqual(snapshot.host, .codex)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.window(.fiveHour)?.remainingPercent, 80)
        XCTAssertEqual(snapshot.window(.sevenDay)?.remainingPercent, 60)
    }
}
