import AppKit
import SwiftUI
import XCTest
@testable import NotchPilotKit

final class AIPluginCompactLayoutTests: XCTestCase {
    private static let compactContext = NotchContext(
        screenID: "test-screen",
        notchState: .previewClosed,
        notchGeometry: NotchGeometry(
            compactSize: CGSize(width: 185, height: 32),
            expandedSize: CGSize(width: 520, height: 320)
        ),
        isPrimaryScreen: true
    )

    @MainActor
    func testCompactMetricsPlaceRuntimeLeftAndTokensInRightColumnForAIHosts() throws {
        let runtimeWidth = measuredWidth(
            "2s",
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        )
        let inputTokenWidth = measuredWidth(
            "↑98.8K",
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
        let outputTokenWidth = measuredWidth(
            "↓1.3K",
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
        let expectedTokenColumnWidth = max(inputTokenWidth, outputTokenWidth)
        let previousHorizontalTokenWidth = inputTokenWidth + 6 + outputTokenWidth

        // .devin is included so we catch any future regression where the new
        // Claude-family host triggers different compact-layout math.
        for host in [AIHost.claude, .codex, .devin] {
            let plugin = CompactMetricsProbePlugin(
                activity: AIPluginCompactActivity(
                    host: host,
                    label: "Working",
                    inputTokenCount: 98_765,
                    outputTokenCount: 1_300,
                    approvalCount: 0,
                    sessionTitle: nil,
                    runtimeDurationText: "2s"
                )
            )

            let metrics = try XCTUnwrap(plugin.compactMetrics(context: Self.compactContext))

            XCTAssertEqual(metrics.leftWidth, 22 + 5 + runtimeWidth, accuracy: 0.5)
            XCTAssertEqual(metrics.rightWidth, expectedTokenColumnWidth, accuracy: 0.5)
            XCTAssertLessThan(metrics.rightWidth, previousHorizontalTokenWidth)
            XCTAssertEqual(
                metrics.sideFrameWidth,
                max(34, metrics.leftWidth, metrics.rightWidth),
                accuracy: 0.5
            )
        }
    }

    @MainActor
    func testCompactMetricsReserveFullWidthForApprovalBadgeText() throws {
        let runtimeWidth = measuredWidth(
            "12s",
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        )
        let badgeWidth = measuredWidth(
            "1",
            font: .systemFont(ofSize: 10, weight: .bold)
        ) + 18
        let plugin = CompactMetricsProbePlugin(
            activity: AIPluginCompactActivity(
                host: .claude,
                label: "Approval",
                inputTokenCount: nil,
                outputTokenCount: nil,
                approvalCount: 1,
                sessionTitle: "Create temporary file",
                runtimeDurationText: "12s"
            )
        )

        let metrics = try XCTUnwrap(plugin.compactMetrics(context: Self.compactContext))

        XCTAssertEqual(
            metrics.leftWidth,
            22 + 5 + badgeWidth + 5 + runtimeWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(metrics.sideFrameWidth, metrics.leftWidth, accuracy: 0.5)
    }

    func testCompactApprovalNoticeLayoutUsesZeroHeightWithoutNotice() {
        let layout = AIPluginCompactApprovalNoticeLayout(
            notice: nil,
            baseTotalWidth: 280
        )

        XCTAssertEqual(layout.totalWidth, 280, accuracy: 0.1)
        XCTAssertEqual(layout.height, 0, accuracy: 0.1)
        XCTAssertEqual(layout.lineLimit, 1)
    }

    func testCompactApprovalNoticeLayoutCanGrowBeyondTwoLines() {
        let layout = AIPluginCompactApprovalNoticeLayout(
            notice: AIPluginApprovalSneakNotice(
                pendingApprovals: [],
                codexSurface: CodexActionableSurface(
                    id: "surface-long",
                    summary: String(
                        repeating: "Do you want me to run the broader notch verification command with the full approval preview visible? ",
                        count: 4
                    ),
                    commandPreview: "/bin/zsh -lc 'swift test'",
                    primaryButtonTitle: "Submit",
                    cancelButtonTitle: "Skip"
                )
            ),
            baseTotalWidth: 280
        )

        XCTAssertGreaterThan(layout.totalWidth, 280)
        XCTAssertGreaterThan(layout.height, 44)
        XCTAssertNil(layout.lineLimit)
    }
}

@MainActor
private final class CompactMetricsProbePlugin: AIPluginRendering {
    let id = "compact-metrics-probe"
    let title = "Compact Metrics Probe"
    let iconSystemName = "sparkles"
    let accentColor: Color = .blue
    var isEnabled = true
    let dockOrder = 1
    let previewPriority: Int? = nil

    var sessions: [AISession] = []
    var pendingApprovals: [PendingApproval] = []
    var codexActionableSurface: CodexActionableSurface? = nil
    var currentCompactActivity: AIPluginCompactActivity?
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] = []
    var approvalSneakNotificationsEnabled = true

    init(activity: AIPluginCompactActivity) {
        self.currentCompactActivity = activity
    }

    func displayTitle(for session: AISession) -> String? { nil }

    func expandedSessionTitle(for session: AISession) -> String {
        hostDisplayName(for: session.host)
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}

private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
}
