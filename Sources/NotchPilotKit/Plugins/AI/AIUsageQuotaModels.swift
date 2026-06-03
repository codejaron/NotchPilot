import Foundation

enum AIUsageQuotaSource: String, Equatable, Sendable {
    case claudeStatusLine
    case codexSessionLog
}

enum AIUsageQuotaWindowKind: String, Equatable, Sendable, Identifiable {
    case fiveHour
    case sevenDay

    var id: String { rawValue }
}

struct AIUsageQuotaWindow: Equatable, Sendable, Identifiable {
    let kind: AIUsageQuotaWindowKind
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?

    var id: AIUsageQuotaWindowKind { kind }

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct AIUsageQuotaSnapshot: Equatable, Sendable, Identifiable {
    let host: AIHost
    let source: AIUsageQuotaSource
    let collectedAt: Date
    let windows: [AIUsageQuotaWindow]
    let planType: String?

    var id: String { "\(host.rawValue)-\(source.rawValue)" }

    func window(_ kind: AIUsageQuotaWindowKind) -> AIUsageQuotaWindow? {
        windows.first { $0.kind == kind }
    }
}

struct AIUsageQuotaHeaderPresentation: Equatable {
    struct Item: Equatable, Identifiable {
        struct Window: Equatable, Identifiable {
            let kind: AIUsageQuotaWindowKind
            let title: String
            let remainingPercentText: String
            let resetText: String?

            var id: AIUsageQuotaWindowKind { kind }
        }

        let host: AIHost
        let title: String
        let windows: [Window]

        var id: AIHost { host }

        var accessibilityText: String {
            ([title] + windows.flatMap { [$0.title, $0.remainingPercentText] }).joined(separator: " ")
        }
    }

    let items: [Item]

    var shouldRender: Bool {
        items.isEmpty == false
    }

    init(snapshots: [AIUsageQuotaSnapshot], now: Date = Date()) {
        items = snapshots
            .sorted { Self.hostOrder($0.host) < Self.hostOrder($1.host) }
            .compactMap { snapshot in
                let windows = Self.orderedWindows(in: snapshot).map { window in
                    Item.Window(
                        kind: window.kind,
                        title: Self.windowTitle(window.kind),
                        remainingPercentText: Self.formattedPercent(window.remainingPercent),
                        resetText: window.resetsAt.map { Self.resetText(for: $0, now: now) }
                    )
                }

                guard windows.isEmpty == false else {
                    return nil
                }

                return Item(
                    host: snapshot.host,
                    title: Self.hostTitle(snapshot.host),
                    windows: windows
                )
            }
    }

    private static func orderedWindows(in snapshot: AIUsageQuotaSnapshot) -> [AIUsageQuotaWindow] {
        [.fiveHour, .sevenDay].compactMap { snapshot.window($0) }
    }

    private static func formattedPercent(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    private static func resetText(for date: Date, now: Date) -> String {
        let remainingSeconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func windowTitle(_ kind: AIUsageQuotaWindowKind) -> String {
        switch kind {
        case .fiveHour:
            return "5h"
        case .sevenDay:
            return "7d"
        }
    }

    private static func hostTitle(_ host: AIHost) -> String {
        switch host {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .devin:
            return "Devin"
        }
    }

    private static func hostOrder(_ host: AIHost) -> Int {
        switch host {
        case .claude:
            return 0
        case .codex:
            return 1
        case .devin:
            return 2
        }
    }
}

extension AIUsageQuotaSnapshot {
    static func isClaudeStatusLine(rawJSON: String) -> Bool {
        guard let root = jsonObject(rawJSON: rawJSON) else {
            return false
        }

        return string(from: root["notchpilot_event_name"])?.lowercased() == "statusline"
    }

    static func claudeStatusLine(rawJSON: String, collectedAt: Date) -> AIUsageQuotaSnapshot? {
        guard let root = jsonObject(rawJSON: rawJSON) else {
            return nil
        }

        let payload = root["payload"] as? [String: Any] ?? root
        guard let rateLimits = payload["rate_limits"] as? [String: Any] else {
            return nil
        }

        let windows = [
            claudeWindow(kind: .fiveHour, value: rateLimits["five_hour"] ?? rateLimits["fiveHour"]),
            claudeWindow(kind: .sevenDay, value: rateLimits["seven_day"] ?? rateLimits["sevenDay"]),
        ].compactMap { $0 }

        guard windows.isEmpty == false else {
            return nil
        }

        return AIUsageQuotaSnapshot(
            host: .claude,
            source: .claudeStatusLine,
            collectedAt: collectedAt,
            windows: windows,
            planType: string(from: rateLimits["plan_type"] ?? rateLimits["planType"] ?? payload["plan_type"] ?? payload["planType"])
        )
    }

    static func isCodexTokenCount(rawJSON: String) -> Bool {
        guard let root = jsonObject(rawJSON: rawJSON) else {
            return false
        }

        let payload = root["payload"] as? [String: Any] ?? root
        return string(from: payload["type"]) == "token_count"
    }

    static func codexTokenCountTimestamp(rawJSON: String) -> Date? {
        guard let root = jsonObject(rawJSON: rawJSON) else {
            return nil
        }

        return date(from: root["timestamp"])
    }

    static func codexSessionLog(rawJSON: String, collectedAt: Date) -> AIUsageQuotaSnapshot? {
        guard let root = jsonObject(rawJSON: rawJSON) else {
            return nil
        }

        let payload = root["payload"] as? [String: Any] ?? root
        guard string(from: payload["type"]) == "token_count" else {
            return nil
        }

        let rateLimits = (root["rate_limits"] as? [String: Any])
            ?? (payload["rate_limits"] as? [String: Any])
        guard let rateLimits else {
            return nil
        }

        let windows = [
            codexWindow(kind: .fiveHour, fallbackWindowMinutes: 300, value: rateLimits["primary"]),
            codexWindow(kind: .sevenDay, fallbackWindowMinutes: 10_080, value: rateLimits["secondary"]),
        ].compactMap { $0 }

        guard windows.isEmpty == false else {
            return nil
        }

        return AIUsageQuotaSnapshot(
            host: .codex,
            source: .codexSessionLog,
            collectedAt: collectedAt,
            windows: windows,
            planType: string(from: rateLimits["plan_type"] ?? rateLimits["planType"])
        )
    }

    private static func claudeWindow(
        kind: AIUsageQuotaWindowKind,
        value: Any?
    ) -> AIUsageQuotaWindow? {
        guard let object = value as? [String: Any] else {
            return nil
        }

        let usedPercent = double(from: object["used_percentage"] ?? object["usedPercentage"])
            ?? double(from: object["used_percent"] ?? object["usedPercent"])
            ?? double(from: object["remaining_percentage"] ?? object["remainingPercentage"]).map { 100 - $0 }
        guard let usedPercent else {
            return nil
        }

        return AIUsageQuotaWindow(
            kind: kind,
            usedPercent: max(0, min(100, usedPercent)),
            resetsAt: date(from: object["resets_at"] ?? object["resetsAt"]),
            windowMinutes: integer(from: object["window_minutes"] ?? object["windowMinutes"])
        )
    }

    private static func codexWindow(
        kind: AIUsageQuotaWindowKind,
        fallbackWindowMinutes: Int,
        value: Any?
    ) -> AIUsageQuotaWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = double(from: object["used_percent"] ?? object["usedPercentage"] ?? object["used_percentage"])
        else {
            return nil
        }

        return AIUsageQuotaWindow(
            kind: kind,
            usedPercent: max(0, min(100, usedPercent)),
            resetsAt: date(from: object["resets_at"] ?? object["resetsAt"]),
            windowMinutes: integer(from: object["window_minutes"] ?? object["windowMinutes"]) ?? fallbackWindowMinutes
        )
    }

    private static func jsonObject(rawJSON: String) -> [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        return object as? [String: Any]
    }

    private static func string(from value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func integer(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func double(from value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func date(from value: Any?) -> Date? {
        if let seconds = double(from: value) {
            let normalizedSeconds = seconds > 10_000_000_000 ? seconds / 1_000 : seconds
            return Date(timeIntervalSince1970: normalizedSeconds)
        }

        guard let string = string(from: value) else {
            return nil
        }
        if let seconds = Double(string) {
            let normalizedSeconds = seconds > 10_000_000_000 ? seconds / 1_000 : seconds
            return Date(timeIntervalSince1970: normalizedSeconds)
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
