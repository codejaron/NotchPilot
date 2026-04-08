import Foundation

struct CodexThreadRegistry {
    private let activityExpiry: TimeInterval
    private var contextsByID: [String: CodexThreadContext] = [:]
    private var lastActiveAtByID: [String: Date] = [:]
    private var latestContextThreadID: String?
    private var currentActiveThreadID: String?

    init(activityExpiry: TimeInterval = 24 * 60 * 60) {
        self.activityExpiry = activityExpiry
    }

    mutating func reset() {
        contextsByID.removeAll()
        lastActiveAtByID.removeAll()
        latestContextThreadID = nil
        currentActiveThreadID = nil
    }

    mutating func apply(_ update: CodexThreadUpdate) {
        let context = update.context
        contextsByID[context.threadID] = context
        latestContextThreadID = context.threadID

        guard update.marksActivity else {
            return
        }

        if let current = lastActiveAtByID[context.threadID] {
            lastActiveAtByID[context.threadID] = max(current, context.updatedAt)
        } else {
            lastActiveAtByID[context.threadID] = context.updatedAt
        }
        currentActiveThreadID = context.threadID
    }

    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-activityExpiry)
        lastActiveAtByID = lastActiveAtByID.filter { _, updatedAt in
            updatedAt >= cutoff
        }

        if let currentActiveThreadID,
           lastActiveAtByID[currentActiveThreadID] == nil {
            self.currentActiveThreadID = nil
        }
    }

    func sessions() -> [AISession] {
        contextsByID.keys.compactMap(session(threadID:)).sorted { $0.updatedAt > $1.updatedAt }
    }

    func session(threadID: String) -> AISession? {
        guard let context = contextsByID[threadID],
              let activeAt = lastActiveAtByID[threadID]
        else {
            return nil
        }

        return AISession(
            id: context.threadID,
            host: .codex,
            lastEventType: eventType(for: context.phase),
            activityLabel: context.activityLabel,
            inputTokenCount: context.inputTokenCount,
            outputTokenCount: context.outputTokenCount,
            updatedAt: activeAt,
            sessionTitle: normalizedTitle(context.title)
        )
    }

    func preferredSession(for surfaceThreadID: String?) -> AISession? {
        if let surfaceThreadID,
           let session = session(threadID: surfaceThreadID) {
            return session
        }

        if let currentActiveThreadID,
           let session = session(threadID: currentActiveThreadID) {
            return session
        }

        return sessions().first
    }

    func preferredContext(for surfaceThreadID: String?) -> CodexThreadContext? {
        if let surfaceThreadID,
           let context = contextsByID[surfaceThreadID] {
            return context
        }

        if let currentActiveThreadID,
           lastActiveAtByID[currentActiveThreadID] != nil,
           let context = contextsByID[currentActiveThreadID] {
            return context
        }

        if let latestContextThreadID,
           let context = contextsByID[latestContextThreadID] {
            return context
        }

        guard let latestActiveThreadID = lastActiveAtByID.max(by: { $0.value < $1.value })?.key else {
            return nil
        }

        return contextsByID[latestActiveThreadID]
    }

    func preferredDisplayTitle(for surfaceThreadID: String?) -> String? {
        normalizedTitle(preferredContext(for: surfaceThreadID)?.title)
    }

    func displayTitle(for session: AISession) -> String? {
        normalizedTitle(contextsByID[session.id]?.title) ?? normalizedTitle(session.sessionTitle)
    }

    private func normalizedTitle(_ rawTitle: String?) -> String? {
        guard let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false
        else {
            return nil
        }

        return title
    }

    private func eventType(for phase: CodexThreadPhase) -> AIBridgeEventType {
        switch phase {
        case .completed:
            return .postToolUse
        case .working, .plan:
            return .unknown("codex/\(phase.rawValue)")
        case .connected:
            return .sessionStart
        case .interrupted:
            return .stop
        case .error, .unknown:
            return .unknown("codex/\(phase.rawValue)")
        }
    }
}
