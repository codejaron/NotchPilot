import AppKit
import SwiftUI

/// Renders the unified AI tab — a single expanded view that combines sessions
/// and approvals from all enabled AI plugins (Claude, Codex, Devin) into one
/// list. Routes user actions back to the correct plugin based on the session
/// or approval's `host`.
///
/// Replaces the per-plugin `AIPluginExpandedView<Plugin>` for the merged tab.
@MainActor
struct AIPluginMergedExpandedView: View {
    let plugins: [any AIPluginRendering]

    @ObservedObject private var settingsStore = SettingsStore.shared
    @State private var approvalReviewState = AIPluginApprovalReviewState()
    @State private var codexSurfaceReviewState = AIPluginCodexSurfaceReviewState()
    @State private var codexApprovalInteractionState: CodexApprovalInteractionState?
    @State private var codexTextDraftSurfaceID: String?
    @State private var codexTextDraft = ""
    @State private var codexTextInputContentHeight: CGFloat = 0
    @State private var claudeFeedbackRequestID: String?
    @State private var claudeFeedbackText = ""
    @State private var claudeFeedbackContentHeight: CGFloat = 0
    @State private var claudeQuestionSelections: [String: Set<String>] = [:]
    @State private var claudeQuestionTextAnswers: [String: String] = [:]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                if let approval = selectedApproval {
                    AIPluginApprovalDetailView(
                        approval: approval,
                        feedbackRequestID: $claudeFeedbackRequestID,
                        feedbackText: $claudeFeedbackText,
                        feedbackContentHeight: $claudeFeedbackContentHeight,
                        questionSelections: $claudeQuestionSelections,
                        questionTextAnswers: $claudeQuestionTextAnswers,
                        onBack: { exitDetail() },
                        onRespond: { action in
                            respond(to: approval, with: action)
                        }
                    )
                } else if let surface = selectedCodexSurface {
                    AIPluginCodexSurfaceView(
                        surface: surface,
                        interactionState: $codexApprovalInteractionState,
                        textDraftSurfaceID: $codexTextDraftSurfaceID,
                        textDraft: $codexTextDraft,
                        textInputContentHeight: $codexTextInputContentHeight,
                        onBack: { exitDetail() },
                        onAction: { action in
                            _ = codexPlugin?.performCodexAction(action, surfaceID: surface.id)
                        },
                        onSelectOption: { optionID in
                            _ = codexPlugin?.selectCodexOption(optionID, surfaceID: surface.id)
                        },
                        onUpdateText: { text in
                            _ = codexPlugin?.updateCodexText(text, surfaceID: surface.id)
                        }
                    )
                } else {
                    sessionListView
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncCurrentCodexSurfaceSelection()
        }
        .onChange(of: combinedApprovalRequestIDs) { _, requestIDs in
            approvalReviewState.syncPendingRequestIDs(requestIDs)
            if let claudeFeedbackRequestID, requestIDs.contains(claudeFeedbackRequestID) == false {
                self.claudeFeedbackRequestID = nil
                self.claudeFeedbackText = ""
                self.claudeFeedbackContentHeight = 0
            }
            claudeQuestionSelections = claudeQuestionSelections.filter { key, _ in
                requestIDs.contains { key.hasPrefix("\($0)::") }
            }
            claudeQuestionTextAnswers = claudeQuestionTextAnswers.filter { key, _ in
                requestIDs.contains { key.hasPrefix("\($0)::") }
            }
        }
        .onChange(of: codexSurface?.id) { _, surfaceID in
            if surfaceID == nil {
                codexSurfaceReviewState.selectedSurfaceID = nil
                codexApprovalInteractionState = nil
                codexTextDraftSurfaceID = nil
                codexTextDraft = ""
                codexTextInputContentHeight = 0
                return
            }

            syncCurrentCodexSurfaceSelection()
        }
    }

    // MARK: - Aggregated state

    private var combinedSummaries: [AIPluginExpandedSessionSummary] {
        Self.combinedSummaries(from: plugins)
    }

    private var combinedApprovals: [PendingApproval] {
        plugins.flatMap(\.pendingApprovals)
    }

    private var combinedApprovalRequestIDs: [String] {
        combinedApprovals.map(\.requestID)
    }

    private var codexPlugin: (any AIPluginRendering)? {
        plugins.first(where: { $0.id == "codex" })
    }

    private var codexSurface: CodexActionableSurface? {
        codexPlugin?.codexActionableSurface
    }

    /// Look up the plugin that owns a given host. Claude and Devin both flow
    /// through `ClaudePlugin`; Codex uses `CodexPlugin`.
    static func plugin(
        for host: AIHost,
        in plugins: [any AIPluginRendering]
    ) -> (any AIPluginRendering)? {
        switch host {
        case .claude, .devin:
            return plugins.first(where: { $0.id == "claude" })
        case .codex:
            return plugins.first(where: { $0.id == "codex" })
        }
    }

    static func combinedSummaries(from plugins: [any AIPluginRendering]) -> [AIPluginExpandedSessionSummary] {
        let phaseOrder: [AIPluginSessionPhase: Int] = [
            .working: 0,
            .plan: 1,
            .connected: 2,
            .interrupted: 3,
            .error: 4,
            .completed: 5,
            .unknown: 6,
        ]

        return plugins
            .flatMap(\.expandedSessionSummaries)
            .sorted { lhs, rhs in
                if lhs.hasAttention != rhs.hasAttention { return lhs.hasAttention }
                let lhsPhase = phaseOrder[lhs.phase] ?? Int.max
                let rhsPhase = phaseOrder[rhs.phase] ?? Int.max
                if lhsPhase != rhsPhase { return lhsPhase < rhsPhase }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    @discardableResult
    static func activate(
        summary: AIPluginExpandedSessionSummary,
        in plugins: [any AIPluginRendering]
    ) -> Bool {
        plugin(for: summary.host, in: plugins)?.activateSession(id: summary.id) ?? false
    }

    static func respond(
        to approval: PendingApproval,
        with action: ApprovalAction,
        in plugins: [any AIPluginRendering]
    ) {
        plugin(for: approval.host, in: plugins)?.respond(to: approval.requestID, with: action)
    }

    // MARK: - Detail selection

    private var selectedApproval: PendingApproval? {
        guard let selectedApprovalRequestID = approvalReviewState.selectedApprovalRequestID else {
            return nil
        }
        return combinedApprovals.first(where: { $0.requestID == selectedApprovalRequestID })
    }

    private var selectedCodexSurface: CodexActionableSurface? {
        guard let selectedSurfaceID = codexSurfaceReviewState.selectedSurfaceID else {
            return nil
        }
        return codexSurface?.id == selectedSurfaceID ? codexSurface : nil
    }

    private func syncCurrentCodexSurfaceSelection() {
        codexSurfaceReviewState.sync(
            currentSurfaceID: codexSurface?.id,
            isReviewingApprovals: approvalReviewState.isReviewingApprovals,
            currentSelectionMatchesSurface: selectedCodexSurface != nil
        )
        codexApprovalInteractionState = nil
        codexTextDraftSurfaceID = nil
        codexTextDraft = ""
        codexTextInputContentHeight = 0
    }

    // MARK: - Session list & action routing

    private var sessionListView: some View {
        AIPluginSessionListView(
            summaries: combinedSummaries,
            onActivate: { summary in
                switch summary.primaryRowAction {
                case .none:
                    break
                case .reviewAttention:
                    if let approvalRequestID = summary.approvalRequestID {
                        codexSurfaceReviewState.selectedSurfaceID = nil
                        approvalReviewState.beginReviewing(requestID: approvalRequestID)
                    } else if let codexSurfaceID = summary.codexSurfaceID {
                        approvalReviewState.exitReviewing()
                        codexSurfaceReviewState.selectedSurfaceID = codexSurfaceID
                        codexApprovalInteractionState = nil
                        codexTextInputContentHeight = 0
                    }
                }
            },
            onJump: { summary in
                _ = Self.activate(summary: summary, in: plugins)
            }
        )
    }

    private func respond(to approval: PendingApproval, with action: ApprovalAction) {
        Self.respond(to: approval, with: action, in: plugins)
    }

    private func exitDetail() {
        approvalReviewState.exitReviewing()
        codexSurfaceReviewState.selectedSurfaceID = nil
        codexApprovalInteractionState = nil
        codexTextDraftSurfaceID = nil
        codexTextDraft = ""
        codexTextInputContentHeight = 0
    }
}
