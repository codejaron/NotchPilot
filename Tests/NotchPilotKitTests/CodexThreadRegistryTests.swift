import XCTest
@testable import NotchPilotKit

final class CodexThreadRegistryTests: XCTestCase {
    func testLiveThreadMetadataRefreshesExistingSessionTitle() {
        var registry = CodexThreadRegistry(activityExpiry: 24 * 60 * 60)

        registry.apply(
            CodexThreadUpdate(
                context: CodexThreadContext(
                    threadID: "thread-1",
                    title: nil,
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 1)
                ),
                marksActivity: true
            )
        )
        registry.apply(
            CodexThreadUpdate(
                context: CodexThreadContext(
                    threadID: "thread-1",
                    title: "Real IPC Title",
                    activityLabel: "Completed",
                    phase: .completed,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
                marksActivity: false
            )
        )

        XCTAssertEqual(registry.sessions().map(\.id), ["thread-1"])
        XCTAssertEqual(registry.sessions().first?.sessionTitle, "Real IPC Title")
        XCTAssertEqual(registry.preferredDisplayTitle(for: nil), "Real IPC Title")
    }

    func testPreferredContextUsesCurrentActiveThreadBeforeLatestMetadataOnlyThread() {
        var registry = CodexThreadRegistry(activityExpiry: 24 * 60 * 60)

        registry.apply(
            CodexThreadUpdate(
                context: CodexThreadContext(
                    threadID: "active-thread",
                    title: "Current Active Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: Date(timeIntervalSince1970: 1)
                ),
                marksActivity: true
            )
        )
        registry.apply(
            CodexThreadUpdate(
                context: CodexThreadContext(
                    threadID: "metadata-thread",
                    title: "Metadata Only Thread",
                    activityLabel: "Connected",
                    phase: .connected,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
                marksActivity: false
            )
        )

        XCTAssertEqual(
            registry.preferredContext(for: nil)?.threadID,
            "active-thread"
        )
        XCTAssertEqual(
            registry.preferredDisplayTitle(for: nil),
            "Current Active Thread"
        )
    }

    func testPreferredDisplayTitleFallsBackToLatestMetadataThreadWhenNoActiveSessionExists() {
        var registry = CodexThreadRegistry(activityExpiry: 24 * 60 * 60)

        registry.apply(
            CodexThreadUpdate(
                context: CodexThreadContext(
                    threadID: "metadata-thread",
                    title: "IPC Current Thread",
                    activityLabel: "Connected",
                    phase: .connected,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
                marksActivity: false
            )
        )

        XCTAssertTrue(registry.sessions().isEmpty)
        XCTAssertEqual(registry.preferredSession(for: nil), nil)
        XCTAssertEqual(registry.preferredDisplayTitle(for: nil), "IPC Current Thread")
    }

    func testPruneRemovesExpiredActiveSessionsButKeepsRecentOnes() {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        var registry = CodexThreadRegistry(activityExpiry: 24 * 60 * 60)

        registry.apply(
            CodexThreadUpdate(
                context: CodexThreadContext(
                    threadID: "stale-thread",
                    title: "Stale Thread",
                    activityLabel: "Completed",
                    phase: .completed,
                    updatedAt: now.addingTimeInterval(-(25 * 60 * 60))
                ),
                marksActivity: true
            )
        )
        registry.apply(
            CodexThreadUpdate(
                context: CodexThreadContext(
                    threadID: "fresh-thread",
                    title: "Fresh Thread",
                    activityLabel: "Working",
                    phase: .working,
                    updatedAt: now.addingTimeInterval(-60)
                ),
                marksActivity: true
            )
        )

        registry.prune(now: now)

        XCTAssertEqual(registry.sessions().map(\.id), ["fresh-thread"])
        XCTAssertEqual(registry.preferredSession(for: nil)?.id, "fresh-thread")
    }
}
