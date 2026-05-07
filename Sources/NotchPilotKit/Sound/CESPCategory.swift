import Foundation

/// CESP v1.0 coding event categories.
///
/// See https://openpeon.com/spec (Section 1) for the authoritative definition.
/// Category names use dotted `{domain}.{event}` notation and MUST NOT be invented
/// outside the spec — unknown names emitted by an IDE are silently skipped by the
/// player.
public enum CESPCategory: String, CaseIterable, Sendable, Hashable {
    // MARK: Core (players MUST support all six)

    case sessionStart = "session.start"
    case taskAcknowledge = "task.acknowledge"
    case taskComplete = "task.complete"
    case taskError = "task.error"
    case inputRequired = "input.required"
    case resourceLimit = "resource.limit"

    // MARK: Extended (optional)

    case userSpam = "user.spam"
    case sessionEnd = "session.end"
    case taskProgress = "task.progress"

    /// The six categories every CESP player MUST support.
    public static let coreCategories: [CESPCategory] = [
        .sessionStart,
        .taskAcknowledge,
        .taskComplete,
        .taskError,
        .inputRequired,
        .resourceLimit,
    ]

    public var isCore: Bool {
        Self.coreCategories.contains(self)
    }
}
