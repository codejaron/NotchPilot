import AppKit
import SwiftUI
import XCTest
@testable import NotchPilotKit

final class AIPluginCompactViewTests: XCTestCase {
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
    func testCompactViewRefreshesRuntimeWithoutPluginEvents() throws {
        let plugin = CompactRuntimeRefreshProbePlugin()
        let metrics = try XCTUnwrap(plugin.compactMetrics(context: Self.compactContext))
        let noticeLayout = AIPluginCompactApprovalNoticeLayout(
            notice: nil,
            baseTotalWidth: metrics.totalWidth
        )
        let view = AIPluginCompactView(
            plugin: plugin,
            context: Self.compactContext,
            approvalNotice: nil,
            noticeLayout: noticeLayout
        )
        let hostingView = NSHostingView(rootView: view)
        let frame = CGRect(
            origin: .zero,
            size: CGSize(width: noticeLayout.totalWidth, height: Self.compactContext.notchGeometry.compactSize.height)
        )
        hostingView.frame = frame

        // TimelineView only schedules periodic updates while hosted in a real
        // window, so attach the hosting view to an offscreen panel for the
        // duration of the assertion.
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        let initialReadCount = plugin.activityReadCount

        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(plugin.activityReadCount, initialReadCount)
    }
}

@MainActor
private final class CompactRuntimeRefreshProbePlugin: AIPluginRendering {
    let id = "compact-runtime-refresh-probe"
    let title = "Compact Runtime Refresh Probe"
    let iconSystemName = "sparkles"
    let accentColor: Color = .blue
    var isEnabled = true
    let dockOrder = 1
    let previewPriority: Int? = nil

    var sessions: [AISession] = []
    var pendingApprovals: [PendingApproval] = []
    var codexActionableSurface: CodexActionableSurface? = nil
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] = []
    var approvalSneakNotificationsEnabled = true
    private(set) var activityReadCount = 0

    var currentCompactActivity: AIPluginCompactActivity? {
        activityReadCount += 1
        return AIPluginCompactActivity(
            host: .claude,
            label: "Working",
            inputTokenCount: 98_765,
            outputTokenCount: 1_300,
            approvalCount: 0,
            sessionTitle: nil,
            runtimeDurationText: "\(activityReadCount)s"
        )
    }

    func displayTitle(for session: AISession) -> String? { nil }

    func expandedSessionTitle(for session: AISession) -> String {
        hostDisplayName(for: session.host)
    }

    func activate(bus: EventBus) {}

    func deactivate() {}
}
