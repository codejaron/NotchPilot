import Foundation

enum SystemMonitorAlertSeverity: Int, Comparable, Sendable {
    case info = 0
    case warn = 1
    case critical = 2

    static func < (lhs: SystemMonitorAlertSeverity, rhs: SystemMonitorAlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum SystemMonitorAlertComparison: String, Sendable {
    case greaterThan
    case lessThan
}

struct SystemMonitorAlertRule: Equatable, Sendable, Identifiable {
    let id: String
    let metric: SystemMonitorMetric
    let comparison: SystemMonitorAlertComparison
    let threshold: Double
    let sustainSeconds: TimeInterval
    let severity: SystemMonitorAlertSeverity

    init(
        id: String,
        metric: SystemMonitorMetric,
        comparison: SystemMonitorAlertComparison,
        threshold: Double,
        sustainSeconds: TimeInterval,
        severity: SystemMonitorAlertSeverity
    ) {
        self.id = id
        self.metric = metric
        self.comparison = comparison
        self.threshold = threshold
        self.sustainSeconds = sustainSeconds
        self.severity = severity
    }
}

extension SystemMonitorAlertRule: CustomStringConvertible {
    var description: String {
        let comparisonText = comparison == .greaterThan ? ">" : "<"
        return "\(id) [\(metric.rawValue) \(comparisonText) \(threshold) for \(sustainSeconds)s · \(severity)]"
    }
}

/// User-facing reactive thresholds. Each value is the *warn-severity* trigger
/// for its metric; critical-severity rules are derived from these in the
/// catalog so the settings UI only needs to expose one number per metric.
///
/// Units intentionally match what users type in the UI:
/// - `cpuPercent`, `memoryPercent`, `batteryPercent` are 0-100 percentages.
/// - `temperatureCelsius` is degrees Celsius.
/// - `diskFreeGB` is gigabytes of free space remaining.
/// - `networkMBps` is megabytes/second on either direction.
struct SystemMonitorAlertThresholds: Equatable, Sendable {
    var cpuPercent: Double
    var memoryPercent: Double
    var temperatureCelsius: Double
    var batteryPercent: Double
    var diskFreeGB: Double
    var networkMBps: Double

    static let `default` = SystemMonitorAlertThresholds(
        cpuPercent: 85,
        memoryPercent: 70,
        temperatureCelsius: 85,
        batteryPercent: 20,
        diskFreeGB: 10,
        networkMBps: 30
    )

    static let cpuPercentRange: ClosedRange<Double> = 50...99
    static let memoryPercentRange: ClosedRange<Double> = 50...99
    static let temperatureCelsiusRange: ClosedRange<Double> = 50...100
    static let batteryPercentRange: ClosedRange<Double> = 5...50
    static let diskFreeGBRange: ClosedRange<Double> = 1...100
    static let networkMBpsRange: ClosedRange<Double> = 5...500

    static let cpuPercentStep: Double = 1
    static let memoryPercentStep: Double = 1
    static let temperatureCelsiusStep: Double = 1
    static let batteryPercentStep: Double = 1
    static let diskFreeGBStep: Double = 1
    static let networkMBpsStep: Double = 1

    func value(for metric: SystemMonitorMetric) -> Double {
        switch metric {
        case .cpu: return cpuPercent
        case .memory: return memoryPercent
        case .temperature: return temperatureCelsius
        case .battery: return batteryPercent
        case .disk: return diskFreeGB
        case .network: return networkMBps
        }
    }

    func setting(_ value: Double, for metric: SystemMonitorMetric) -> SystemMonitorAlertThresholds {
        var copy = self
        switch metric {
        case .cpu:
            copy.cpuPercent = value.clamped(to: Self.cpuPercentRange)
        case .memory:
            copy.memoryPercent = value.clamped(to: Self.memoryPercentRange)
        case .temperature:
            copy.temperatureCelsius = value.clamped(to: Self.temperatureCelsiusRange)
        case .battery:
            copy.batteryPercent = value.clamped(to: Self.batteryPercentRange)
        case .disk:
            copy.diskFreeGB = value.clamped(to: Self.diskFreeGBRange)
        case .network:
            copy.networkMBps = value.clamped(to: Self.networkMBpsRange)
        }
        return copy
    }

    static func range(for metric: SystemMonitorMetric) -> ClosedRange<Double> {
        switch metric {
        case .cpu: return cpuPercentRange
        case .memory: return memoryPercentRange
        case .temperature: return temperatureCelsiusRange
        case .battery: return batteryPercentRange
        case .disk: return diskFreeGBRange
        case .network: return networkMBpsRange
        }
    }

    static func step(for metric: SystemMonitorMetric) -> Double {
        switch metric {
        case .cpu: return cpuPercentStep
        case .memory: return memoryPercentStep
        case .temperature: return temperatureCelsiusStep
        case .battery: return batteryPercentStep
        case .disk: return diskFreeGBStep
        case .network: return networkMBpsStep
        }
    }
}

enum SystemMonitorAlertRuleCatalog {
    /// Default rule list, derived from `SystemMonitorAlertThresholds.default`.
    /// Threshold units mirror `SystemMonitorAlertEngine.metricValue` (percent for ratios,
    /// celsius for temperature, GB for free disk, bytes/sec for network throughput).
    static let defaults: [SystemMonitorAlertRule] = rules(for: .default)

    /// Builds the canonical rule list for a given user-tunable threshold set.
    /// Critical-severity rules are derived from the warn value so users only
    /// need to think about a single sensitivity number per metric.
    static func rules(for thresholds: SystemMonitorAlertThresholds) -> [SystemMonitorAlertRule] {
        [
            SystemMonitorAlertRule(
                id: "cpu.warn",
                metric: .cpu,
                comparison: .greaterThan,
                threshold: thresholds.cpuPercent,
                sustainSeconds: 5,
                severity: .warn
            ),
            SystemMonitorAlertRule(
                id: "memory.warn",
                metric: .memory,
                comparison: .greaterThan,
                threshold: thresholds.memoryPercent,
                sustainSeconds: 0,
                severity: .warn
            ),
            SystemMonitorAlertRule(
                id: "memory.critical",
                metric: .memory,
                comparison: .greaterThan,
                threshold: min(thresholds.memoryPercent + 15, 99),
                sustainSeconds: 0,
                severity: .critical
            ),
            SystemMonitorAlertRule(
                id: "temperature.warn",
                metric: .temperature,
                comparison: .greaterThan,
                threshold: thresholds.temperatureCelsius,
                sustainSeconds: 3,
                severity: .warn
            ),
            SystemMonitorAlertRule(
                id: "temperature.critical",
                metric: .temperature,
                comparison: .greaterThan,
                threshold: thresholds.temperatureCelsius + 10,
                sustainSeconds: 1,
                severity: .critical
            ),
            SystemMonitorAlertRule(
                id: "battery.warn",
                metric: .battery,
                comparison: .lessThan,
                threshold: thresholds.batteryPercent,
                sustainSeconds: 0,
                severity: .warn
            ),
            SystemMonitorAlertRule(
                id: "battery.critical",
                metric: .battery,
                comparison: .lessThan,
                threshold: max(thresholds.batteryPercent / 2, 1),
                sustainSeconds: 0,
                severity: .critical
            ),
            SystemMonitorAlertRule(
                id: "disk.warn",
                metric: .disk,
                comparison: .lessThan,
                threshold: thresholds.diskFreeGB,
                sustainSeconds: 0,
                severity: .warn
            ),
            SystemMonitorAlertRule(
                id: "disk.critical",
                metric: .disk,
                comparison: .lessThan,
                threshold: max(thresholds.diskFreeGB / 3, 1),
                sustainSeconds: 0,
                severity: .critical
            ),
            SystemMonitorAlertRule(
                id: "network.spike",
                metric: .network,
                comparison: .greaterThan,
                threshold: thresholds.networkMBps * 1_000_000,
                sustainSeconds: 3,
                severity: .info
            ),
        ]
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

struct SystemMonitorActiveAlert: Equatable, Sendable {
    let metric: SystemMonitorMetric
    let severity: SystemMonitorAlertSeverity
    let value: Double
    let firedAt: Date
    let triggeringRuleID: String
}

enum SystemMonitorAlertChange: Equatable, Sendable {
    case fired(SystemMonitorActiveAlert)
    case escalated(SystemMonitorActiveAlert, previousSeverity: SystemMonitorAlertSeverity)
    case cleared(metric: SystemMonitorMetric)
}

protocol SystemMonitorClock: Sendable {
    func now() -> Date
}

struct SystemMonitorSystemClock: SystemMonitorClock {
    init() {}
    func now() -> Date { Date() }
}

/// Stateful threshold evaluator for `SystemMonitorSnapshot` streams.
///
/// Each rule carries its own debounce window (`sustainSeconds`). When any rule
/// for a metric fires, the engine emits the rule with the *highest* severity as
/// the canonical alert for that metric, so callers do not need to perform their
/// own dedup. The engine is intentionally non-isolated so it can be used from
/// either main-actor or test contexts.
final class SystemMonitorAlertEngine {
    private struct RuleState {
        var pendingSince: Date?
        var firing: Bool
    }

    private(set) var rules: [SystemMonitorAlertRule]
    private var ruleStates: [String: RuleState] = [:]
    private var firingRuleAlerts: [String: SystemMonitorActiveAlert] = [:]
    private var activeAlerts: [SystemMonitorMetric: SystemMonitorActiveAlert] = [:]
    private let clock: any SystemMonitorClock

    init(
        rules: [SystemMonitorAlertRule] = SystemMonitorAlertRuleCatalog.defaults,
        clock: any SystemMonitorClock = SystemMonitorSystemClock()
    ) {
        self.rules = rules
        self.clock = clock
    }

    var currentAlerts: [SystemMonitorMetric: SystemMonitorActiveAlert] {
        activeAlerts
    }

    var firingMetrics: Set<SystemMonitorMetric> {
        Set(activeAlerts.keys)
    }

    func reset() {
        ruleStates.removeAll()
        firingRuleAlerts.removeAll()
        activeAlerts.removeAll()
    }

    func updateRules(_ rules: [SystemMonitorAlertRule]) {
        self.rules = rules
        let validIDs = Set(rules.map(\.id))
        ruleStates = ruleStates.filter { validIDs.contains($0.key) }
        firingRuleAlerts = firingRuleAlerts.filter { validIDs.contains($0.key) }
        activeAlerts = recomputeAlerts(from: firingRuleAlerts)
    }

    @discardableResult
    func process(snapshot: SystemMonitorSnapshot) -> [SystemMonitorAlertChange] {
        let now = clock.now()
        var ruleChanges: [(metric: SystemMonitorMetric, kind: RuleChangeKind)] = []

        for rule in rules {
            let value = Self.metricValue(for: rule.metric, snapshot: snapshot)
            let isCrossed = Self.evaluate(rule: rule, value: value)
            var state = ruleStates[rule.id] ?? RuleState(pendingSince: nil, firing: false)

            if isCrossed {
                if state.firing {
                    if let observed = value,
                       let existing = firingRuleAlerts[rule.id],
                       existing.value != observed {
                        let updated = SystemMonitorActiveAlert(
                            metric: rule.metric,
                            severity: rule.severity,
                            value: observed,
                            firedAt: existing.firedAt,
                            triggeringRuleID: rule.id
                        )
                        firingRuleAlerts[rule.id] = updated
                    }
                } else {
                    let pendingSince = state.pendingSince ?? now
                    state.pendingSince = pendingSince
                    if now.timeIntervalSince(pendingSince) >= rule.sustainSeconds {
                        state.firing = true
                        state.pendingSince = nil
                        let alert = SystemMonitorActiveAlert(
                            metric: rule.metric,
                            severity: rule.severity,
                            value: value ?? rule.threshold,
                            firedAt: now,
                            triggeringRuleID: rule.id
                        )
                        firingRuleAlerts[rule.id] = alert
                        ruleChanges.append((rule.metric, .ruleFired))
                    }
                }
            } else {
                state.pendingSince = nil
                if state.firing {
                    state.firing = false
                    firingRuleAlerts.removeValue(forKey: rule.id)
                    ruleChanges.append((rule.metric, .ruleCleared))
                }
            }

            ruleStates[rule.id] = state
        }

        let updatedAlerts = recomputeAlerts(from: firingRuleAlerts)
        let changes = diffAlerts(previous: activeAlerts, current: updatedAlerts)
        activeAlerts = updatedAlerts
        _ = ruleChanges
        return changes
    }

    static func metricValue(
        for metric: SystemMonitorMetric,
        snapshot: SystemMonitorSnapshot
    ) -> Double? {
        switch metric {
        case .cpu:
            return snapshot.cpuUsage.map { $0 * 100 }
        case .memory:
            if let pressure = snapshot.memoryPressure {
                return pressure * 100
            }
            return snapshot.memoryUsage.map { $0 * 100 }
        case .network:
            let download = snapshot.downloadBytesPerSecond ?? 0
            let upload = snapshot.uploadBytesPerSecond ?? 0
            let combined = max(download, upload)
            return combined > 0 ? combined : nil
        case .temperature:
            return snapshot.temperatureCelsius
        case .disk:
            return snapshot.diskFreeBytes.map { Double($0) / 1_000_000_000 }
        case .battery:
            return snapshot.batteryPercent.map { $0 * 100 }
        }
    }

    static func evaluate(rule: SystemMonitorAlertRule, value: Double?) -> Bool {
        guard let value else { return false }
        switch rule.comparison {
        case .greaterThan:
            return value > rule.threshold
        case .lessThan:
            return value < rule.threshold
        }
    }

    private enum RuleChangeKind {
        case ruleFired
        case ruleCleared
    }

    private func recomputeAlerts(
        from firingRuleAlerts: [String: SystemMonitorActiveAlert]
    ) -> [SystemMonitorMetric: SystemMonitorActiveAlert] {
        var result: [SystemMonitorMetric: SystemMonitorActiveAlert] = [:]
        for alert in firingRuleAlerts.values {
            if let existing = result[alert.metric] {
                if alert.severity > existing.severity {
                    result[alert.metric] = alert
                } else if alert.severity == existing.severity, alert.firedAt < existing.firedAt {
                    result[alert.metric] = alert
                }
            } else {
                result[alert.metric] = alert
            }
        }
        return result
    }

    private func diffAlerts(
        previous: [SystemMonitorMetric: SystemMonitorActiveAlert],
        current: [SystemMonitorMetric: SystemMonitorActiveAlert]
    ) -> [SystemMonitorAlertChange] {
        var changes: [SystemMonitorAlertChange] = []

        for (metric, alert) in current {
            if let existing = previous[metric] {
                if alert.severity > existing.severity {
                    changes.append(.escalated(alert, previousSeverity: existing.severity))
                }
            } else {
                changes.append(.fired(alert))
            }
        }

        for metric in previous.keys where current[metric] == nil {
            changes.append(.cleared(metric: metric))
        }

        return changes
    }
}
