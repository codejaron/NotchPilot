import AppKit
import SwiftUI

@MainActor
protocol AIPluginRendering: NotchPlugin {
    var sessions: [AISession] { get }
    var pendingApprovals: [PendingApproval] { get }
    var codexActionableSurface: CodexActionableSurface? { get }
    var currentCompactActivity: AIPluginCompactActivity? { get }
    var expandedSessionSummaries: [AIPluginExpandedSessionSummary] { get }
    var approvalSneakNotificationsEnabled: Bool { get }
    var activitySneakPreviewsHidden: Bool { get }

    func displayTitle(for session: AISession) -> String?
    func expandedSessionTitle(for session: AISession) -> String
    func preferredCodexTitle(for surface: CodexActionableSurface?) -> String?
    @discardableResult
    func activateSession(id: String) -> Bool
    func respond(to requestID: String, with action: ApprovalAction)

    @discardableResult
    func performCodexAction(_ action: CodexSurfaceAction, surfaceID: String) -> Bool

    @discardableResult
    func selectCodexOption(_ optionID: String, surfaceID: String) -> Bool

    @discardableResult
    func updateCodexText(_ text: String, surfaceID: String) -> Bool
}

extension AIPluginRendering {
    public func preview(context: NotchContext) -> NotchPluginPreview? {
        guard isEnabled, shouldRenderCompactPreview else {
            return nil
        }
        guard let metrics = compactMetrics(context: context) else {
            return nil
        }
        let approvalNotice = approvalSneakNotice()
        let noticeLayout = AIPluginCompactApprovalNoticeLayout(
            notice: approvalNotice,
            baseTotalWidth: metrics.totalWidth
        )

        return NotchPluginPreview(
            width: noticeLayout.totalWidth,
            height: context.notchGeometry.compactSize.height + noticeLayout.height,
            view: AnyView(
                AIPluginCompactView(
                    plugin: self,
                    context: context,
                    approvalNotice: approvalNotice,
                    noticeLayout: noticeLayout
                )
            )
        )
    }

    public func contentView(context: NotchContext) -> AnyView {
        // AI plugins are rendered via `AIPluginMergedExpandedView` from the
        // shell layer (see `NotchContentView.aiMergedViewport`); this default
        // implementation only exists to satisfy the `NotchPlugin` requirement
        // and is never exercised at runtime.
        AnyView(EmptyView())
    }

    var shouldRenderCompactPreview: Bool {
        guard isEnabled else {
            return false
        }

        if approvalSneakNotificationsEnabled && approvalDrivenCompactPreviewAvailable {
            return true
        }

        guard activitySneakPreviewsHidden == false else {
            return false
        }

        return compactPreviewSession() != nil
    }

    func compactPreviewSession() -> AISession? {
        sessions
            .filter(\.isLiveCompactPreviewCandidate)
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    func compactMetrics(context: NotchContext) -> AIPluginCompactMetrics? {
        guard let activity = currentCompactActivity else {
            return nil
        }

        let runtimeWidth = compactRuntimeWidth(activity.runtimeDurationText)
        let leftWidth =
            22
            + (activity.approvalCount > 0 ? 5 + approvalBadgeWidth(count: activity.approvalCount) : 0)
            + (runtimeWidth > 0 ? 5 + runtimeWidth : 0)

        let rightWidth = tokenColumnWidth(
            input: activity.inputTokenCount,
            output: activity.outputTokenCount
        )

        let sideFrameWidth = max(34, leftWidth, rightWidth)
        let totalWidth =
            AIPluginCompactPadding.outerPadding * 2
            + context.notchGeometry.compactSize.width
            + sideFrameWidth * 2

        return AIPluginCompactMetrics(
            leftWidth: leftWidth,
            rightWidth: rightWidth,
            sideFrameWidth: sideFrameWidth,
            totalWidth: totalWidth
        )
    }

    func expandedSessionTitle(for session: AISession) -> String {
        displayTitle(for: session) ?? hostDisplayName(for: session.host)
    }

    func preferredCodexTitle(for surface: CodexActionableSurface?) -> String? { nil }

    @discardableResult
    func activateSession(id: String) -> Bool { false }

    var approvalSneakNotificationsEnabled: Bool {
        SettingsStore.shared.approvalSneakNotificationsEnabled
    }

    var activitySneakPreviewsHidden: Bool {
        SettingsStore.shared.activitySneakPreviewsHidden
    }

    func approvalSneakNotice() -> AIPluginApprovalSneakNotice? {
        guard approvalSneakNotificationsEnabled else {
            return nil
        }

        return AIPluginApprovalSneakNotice(
            pendingApprovals: pendingApprovals,
            codexSurface: codexActionableSurface
        )
    }

    func respond(to requestID: String, with action: ApprovalAction) {}

    @discardableResult
    func performCodexAction(_ action: CodexSurfaceAction, surfaceID: String) -> Bool { false }

    @discardableResult
    func selectCodexOption(_ optionID: String, surfaceID: String) -> Bool { false }

    @discardableResult
    func updateCodexText(_ text: String, surfaceID: String) -> Bool { false }

    func hostDisplayName(for host: AIHost) -> String {
        switch host {
        case .claude:
            return "Claude Code"
        case .codex:
            return "OpenAI Codex"
        case .devin:
            return "Devin"
        }
    }

    private var approvalDrivenCompactPreviewAvailable: Bool {
        codexActionableSurface != nil || pendingApprovals.isEmpty == false
    }

    func formattedTokenCount(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func tokenWidth(symbol: String, value: Int?) -> CGFloat {
        AICompactTextMeasurer.width(
            "\(symbol)\(formattedTokenCount(value))",
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
    }

    private func tokenColumnWidth(input: Int?, output: Int?) -> CGFloat {
        guard input != nil || output != nil else {
            return 0
        }

        return max(
            tokenWidth(symbol: "↑", value: input),
            tokenWidth(symbol: "↓", value: output)
        )
    }

    private func compactRuntimeWidth(_ runtime: String?) -> CGFloat {
        guard let runtime,
              runtime.isEmpty == false
        else {
            return 0
        }

        return AICompactTextMeasurer.width(
            runtime,
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        )
    }

    private func approvalBadgeWidth(count: Int) -> CGFloat {
        AICompactTextMeasurer.width(
            "\(count)",
            font: .systemFont(ofSize: 10, weight: .bold)
        ) + 18
    }
}

private extension AISession {
    var isLiveCompactPreviewCandidate: Bool {
        switch lastEventType {
        case .preToolUse, .postToolUse, .userPromptSubmit, .unknown:
            return true
        case .permissionRequest, .sessionStart, .stop:
            return false
        }
    }
}
