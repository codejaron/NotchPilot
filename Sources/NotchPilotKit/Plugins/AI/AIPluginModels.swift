import AppKit
import SwiftUI

struct AIPluginCompactActivity: Equatable {
    let host: AIHost
    let label: String
    let inputTokenCount: Int?
    let outputTokenCount: Int?
    let approvalCount: Int
    let sessionTitle: String?
    let runtimeDurationText: String?
}

enum AIRuntimeDurationFormatter {
    static func format(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))m"
        }
        if minutes > 0 {
            return "\(minutes)m\(String(format: "%02d", seconds))s"
        }
        return "\(seconds)s"
    }
}

struct AIPluginExpandedSessionSummary: Equatable, Identifiable {
    let id: String
    let host: AIHost
    let title: String
    let subtitle: String
    let phase: AIPluginSessionPhase
    let approvalCount: Int
    let approvalRequestID: String?
    let codexSurfaceID: String?
    let updatedAt: Date
    let inputTokenCount: Int?
    let outputTokenCount: Int?
    let runtimeDurationText: String?

    init(
        id: String,
        host: AIHost,
        title: String,
        subtitle: String,
        phase: AIPluginSessionPhase,
        approvalCount: Int,
        approvalRequestID: String?,
        codexSurfaceID: String?,
        updatedAt: Date,
        inputTokenCount: Int?,
        outputTokenCount: Int?,
        runtimeDurationText: String? = nil
    ) {
        self.id = id
        self.host = host
        self.title = title
        self.subtitle = subtitle
        self.phase = phase
        self.approvalCount = approvalCount
        self.approvalRequestID = approvalRequestID
        self.codexSurfaceID = codexSurfaceID
        self.updatedAt = updatedAt
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.runtimeDurationText = runtimeDurationText
    }

    var hasAttention: Bool {
        approvalRequestID != nil || codexSurfaceID != nil
    }

    var primaryRowAction: AIPluginSessionRowPrimaryAction {
        hasAttention ? .reviewAttention : .none
    }

    var jumpAccessoryHitWidth: CGFloat {
        38
    }

    var isDimmed: Bool {
        phase == .completed
    }

    var hasTokenUsage: Bool {
        inputTokenCount != nil || outputTokenCount != nil
    }

    var hasRuntime: Bool {
        guard let runtimeDurationText else { return false }
        return runtimeDurationText.isEmpty == false
    }

    var hasMeta: Bool {
        hasTokenUsage || hasRuntime
    }
}

enum AIPluginSessionRowPrimaryAction: Equatable {
    case none
    case reviewAttention
}

struct AIPluginSessionJumpAccessoryPresentation: Equatable {
    let isRowDimmed: Bool

    init(isRowDimmed: Bool) {
        self.isRowDimmed = isRowDimmed
    }

    var primaryContentOpacity: Double {
        isRowDimmed ? 0.58 : 1
    }

    var symbolSystemName: String {
        "arrow.up.forward"
    }

    var symbolOpacity: Double {
        isRowDimmed ? 0.72 : 0.82
    }

    var backgroundOpacity: Double {
        isRowDimmed ? 0.075 : 0.06
    }

    var borderOpacity: Double {
        isRowDimmed ? 0.14 : 0.12
    }

    var effectiveSymbolOpacity: Double {
        symbolOpacity
    }

    var iconFrameSize: CGFloat {
        24
    }

    var hitHeight: CGFloat {
        38
    }
}

enum AIPluginSessionPhase: Equatable {
    case plan
    case working
    case completed
    case connected
    case interrupted
    case error
    case unknown

    init(codexPhase: CodexThreadPhase) {
        switch codexPhase {
        case .plan:
            self = .plan
        case .working:
            self = .working
        case .completed:
            self = .completed
        case .connected:
            self = .connected
        case .interrupted:
            self = .interrupted
        case .error:
            self = .error
        case .unknown:
            self = .unknown
        }
    }
}
