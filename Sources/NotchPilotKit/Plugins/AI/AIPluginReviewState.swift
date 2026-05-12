import AppKit
import SwiftUI

struct AIPluginExpandedSessionListPresentation: Equatable {
    let summaries: [AIPluginExpandedSessionSummary]

    var shouldRender: Bool {
        summaries.isEmpty == false
    }
}

struct AIPluginApprovalReviewState: Equatable {
    var isReviewingApprovals = false
    var selectedApprovalRequestID: String?

    mutating func beginReviewing(requestID: String) {
        isReviewingApprovals = true
        selectedApprovalRequestID = requestID
    }

    mutating func exitReviewing() {
        isReviewingApprovals = false
        selectedApprovalRequestID = nil
    }

    mutating func syncPendingRequestIDs(_ requestIDs: [String]) {
        guard isReviewingApprovals else {
            if requestIDs.isEmpty {
                selectedApprovalRequestID = nil
            }
            return
        }

        if let selectedApprovalRequestID,
           requestIDs.contains(selectedApprovalRequestID) {
            return
        }

        selectedApprovalRequestID = requestIDs.first
        if selectedApprovalRequestID == nil {
            isReviewingApprovals = false
        }
    }
}

struct AIPluginCodexSurfaceReviewState: Equatable {
    var selectedSurfaceID: String?

    mutating func sync(
        currentSurfaceID: String?,
        isReviewingApprovals: Bool,
        currentSelectionMatchesSurface: Bool
    ) {
        guard isReviewingApprovals == false else {
            return
        }

        guard let currentSurfaceID else {
            selectedSurfaceID = nil
            return
        }

        guard let selectedSurfaceID else {
            return
        }

        guard currentSelectionMatchesSurface == false else {
            return
        }

        self.selectedSurfaceID = selectedSurfaceID == currentSurfaceID ? selectedSurfaceID : currentSurfaceID
    }
}
