import XCTest
@testable import NotchPilotKit

final class SystemMonitorAlertEngineTests: XCTestCase {
    // MARK: - Threshold + sustain debounce

    func testCpuRuleFiresOnlyAfterSustainWindow() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let rule = SystemMonitorAlertRule(
            id: "cpu.warn",
            metric: .cpu,
            comparison: .greaterThan,
            threshold: 85,
            sustainSeconds: 5,
            severity: .warn
        )
        let engine = SystemMonitorAlertEngine(rules: [rule], clock: clock)

        let crossingChanges = engine.process(snapshot: snapshot(cpuUsage: 0.95))
        XCTAssertTrue(crossingChanges.isEmpty, "Rule should not fire before sustainSeconds elapses")
        XCTAssertTrue(engine.currentAlerts.isEmpty)

        clock.advance(by: 4)
        XCTAssertTrue(engine.process(snapshot: snapshot(cpuUsage: 0.95)).isEmpty)
        XCTAssertTrue(engine.currentAlerts.isEmpty)

        clock.advance(by: 1)
        let firedChanges = engine.process(snapshot: snapshot(cpuUsage: 0.95))
        XCTAssertEqual(firedChanges.count, 1)
        guard case let .fired(alert) = firedChanges.first else {
            XCTFail("Expected fired change")
            return
        }
        XCTAssertEqual(alert.metric, .cpu)
        XCTAssertEqual(alert.severity, .warn)
        XCTAssertEqual(alert.value, 95, accuracy: 0.001)
        XCTAssertEqual(engine.currentAlerts[.cpu]?.severity, .warn)
    }

    func testCpuRuleResetsPendingTimerWhenValueDropsBeforeFiring() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let rule = SystemMonitorAlertRule(
            id: "cpu.warn",
            metric: .cpu,
            comparison: .greaterThan,
            threshold: 85,
            sustainSeconds: 5,
            severity: .warn
        )
        let engine = SystemMonitorAlertEngine(rules: [rule], clock: clock)

        _ = engine.process(snapshot: snapshot(cpuUsage: 0.9))
        clock.advance(by: 3)
        _ = engine.process(snapshot: snapshot(cpuUsage: 0.5))
        clock.advance(by: 6)
        let changes = engine.process(snapshot: snapshot(cpuUsage: 0.95))
        XCTAssertTrue(changes.isEmpty, "Rule should require a fresh sustain window after dropping below threshold")
        XCTAssertTrue(engine.currentAlerts.isEmpty)
    }

    func testRuleFiresImmediatelyWhenSustainIsZero() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let rule = SystemMonitorAlertRule(
            id: "memory.warn",
            metric: .memory,
            comparison: .greaterThan,
            threshold: 70,
            sustainSeconds: 0,
            severity: .warn
        )
        let engine = SystemMonitorAlertEngine(rules: [rule], clock: clock)

        let changes = engine.process(snapshot: snapshot(memoryPressure: 0.75))
        guard case .fired(let alert)? = changes.first else {
            XCTFail("Expected immediate fire when sustainSeconds is 0")
            return
        }
        XCTAssertEqual(alert.metric, .memory)
        XCTAssertEqual(alert.value, 75, accuracy: 0.001)
    }

    // MARK: - Severity merging

    func testHighestSeverityWinsWhenMultipleRulesFireOnSameMetric() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let warn = SystemMonitorAlertRule(
            id: "memory.warn",
            metric: .memory,
            comparison: .greaterThan,
            threshold: 70,
            sustainSeconds: 0,
            severity: .warn
        )
        let critical = SystemMonitorAlertRule(
            id: "memory.critical",
            metric: .memory,
            comparison: .greaterThan,
            threshold: 85,
            sustainSeconds: 0,
            severity: .critical
        )
        let engine = SystemMonitorAlertEngine(rules: [warn, critical], clock: clock)

        let changes = engine.process(snapshot: snapshot(memoryPressure: 0.9))
        // Only one fired change should be reported per metric, with the
        // highest severity selected.
        let firedAlerts: [SystemMonitorActiveAlert] = changes.compactMap {
            if case let .fired(alert) = $0 { return alert }
            return nil
        }
        XCTAssertEqual(firedAlerts.count, 1)
        XCTAssertEqual(firedAlerts.first?.severity, .critical)
        XCTAssertEqual(engine.currentAlerts[.memory]?.severity, .critical)
    }

    func testEscalationFromWarnToCriticalEmitsEscalatedChange() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let warn = SystemMonitorAlertRule(
            id: "memory.warn",
            metric: .memory,
            comparison: .greaterThan,
            threshold: 70,
            sustainSeconds: 0,
            severity: .warn
        )
        let critical = SystemMonitorAlertRule(
            id: "memory.critical",
            metric: .memory,
            comparison: .greaterThan,
            threshold: 85,
            sustainSeconds: 0,
            severity: .critical
        )
        let engine = SystemMonitorAlertEngine(rules: [warn, critical], clock: clock)

        _ = engine.process(snapshot: snapshot(memoryPressure: 0.75))
        XCTAssertEqual(engine.currentAlerts[.memory]?.severity, .warn)

        let changes = engine.process(snapshot: snapshot(memoryPressure: 0.9))
        let escalated: SystemMonitorActiveAlert? = changes.compactMap {
            if case let .escalated(alert, previous) = $0 {
                XCTAssertEqual(previous, .warn)
                return alert
            }
            return nil
        }.first
        XCTAssertEqual(escalated?.severity, .critical)
        XCTAssertEqual(engine.currentAlerts[.memory]?.severity, .critical)
    }

    // MARK: - Clearing

    func testRuleClearsAfterValueDropsBackBelowThreshold() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let rule = SystemMonitorAlertRule(
            id: "battery.warn",
            metric: .battery,
            comparison: .lessThan,
            threshold: 20,
            sustainSeconds: 0,
            severity: .warn
        )
        let engine = SystemMonitorAlertEngine(rules: [rule], clock: clock)

        _ = engine.process(snapshot: snapshot(batteryPercent: 0.15))
        XCTAssertEqual(engine.currentAlerts[.battery]?.severity, .warn)

        let changes = engine.process(snapshot: snapshot(batteryPercent: 0.5))
        XCTAssertTrue(engine.currentAlerts.isEmpty)
        XCTAssertTrue(changes.contains { change in
            if case let .cleared(metric) = change, metric == .battery {
                return true
            }
            return false
        })
    }

    func testRuleStaysFiringWhileValueRemainsAboveThresholdWithNoChange() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let rule = SystemMonitorAlertRule(
            id: "memory.warn",
            metric: .memory,
            comparison: .greaterThan,
            threshold: 70,
            sustainSeconds: 0,
            severity: .warn
        )
        let engine = SystemMonitorAlertEngine(rules: [rule], clock: clock)

        _ = engine.process(snapshot: snapshot(memoryPressure: 0.75))
        let secondPass = engine.process(snapshot: snapshot(memoryPressure: 0.75))
        XCTAssertTrue(secondPass.isEmpty, "Steady state should not emit duplicate fired changes")
        XCTAssertEqual(engine.currentAlerts[.memory]?.severity, .warn)
    }

    // MARK: - Reset

    func testResetClearsAllStateAndAlerts() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let rule = SystemMonitorAlertRule(
            id: "memory.warn",
            metric: .memory,
            comparison: .greaterThan,
            threshold: 70,
            sustainSeconds: 0,
            severity: .warn
        )
        let engine = SystemMonitorAlertEngine(rules: [rule], clock: clock)

        _ = engine.process(snapshot: snapshot(memoryPressure: 0.9))
        XCTAssertFalse(engine.currentAlerts.isEmpty)

        engine.reset()
        XCTAssertTrue(engine.currentAlerts.isEmpty)

        // After reset, sustainSeconds=0 rule should fire immediately again.
        let changes = engine.process(snapshot: snapshot(memoryPressure: 0.9))
        XCTAssertEqual(changes.count, 1)
    }

    // MARK: - Default catalog sanity

    func testDefaultCatalogContainsAtLeastOneRulePerMetric() {
        let metrics = Set(SystemMonitorAlertRuleCatalog.defaults.map(\.metric))
        XCTAssertTrue(metrics.contains(.cpu))
        XCTAssertTrue(metrics.contains(.memory))
        XCTAssertTrue(metrics.contains(.temperature))
        XCTAssertTrue(metrics.contains(.battery))
        XCTAssertTrue(metrics.contains(.disk))
        XCTAssertTrue(metrics.contains(.network))
    }

    func testDefaultCatalogIDsAreUnique() {
        let ids = SystemMonitorAlertRuleCatalog.defaults.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Tunable threshold catalog

    func testParametricCatalogPropagatesUserThresholdsIntoWarnRules() {
        let custom = SystemMonitorAlertThresholds(
            cpuPercent: 60,
            memoryPercent: 55,
            temperatureCelsius: 70,
            batteryPercent: 35,
            diskFreeGB: 25,
            networkMBps: 50
        )
        let rules = SystemMonitorAlertRuleCatalog.rules(for: custom)
        let byID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })

        XCTAssertEqual(byID["cpu.warn"]?.threshold, 60)
        XCTAssertEqual(byID["memory.warn"]?.threshold, 55)
        XCTAssertEqual(byID["temperature.warn"]?.threshold, 70)
        XCTAssertEqual(byID["battery.warn"]?.threshold, 35)
        XCTAssertEqual(byID["disk.warn"]?.threshold, 25)
        // Network threshold is supplied in MB/s but stored in bytes/s so the
        // engine can compare against raw counters.
        XCTAssertEqual(byID["network.spike"]?.threshold, 50_000_000)
    }

    func testParametricCatalogDerivesCriticalThresholdsFromUserWarnValues() {
        let custom = SystemMonitorAlertThresholds(
            cpuPercent: 60,
            memoryPercent: 55,
            temperatureCelsius: 70,
            batteryPercent: 30,
            diskFreeGB: 30,
            networkMBps: 50
        )
        let rules = SystemMonitorAlertRuleCatalog.rules(for: custom)
        let byID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })

        XCTAssertEqual(byID["memory.critical"]?.threshold, 70)        // 55 + 15
        XCTAssertEqual(byID["temperature.critical"]?.threshold, 80)   // 70 + 10
        XCTAssertEqual(byID["battery.critical"]?.threshold, 15)       // 30 / 2
        XCTAssertEqual(byID["disk.critical"]?.threshold, 10)          // 30 / 3
    }

    func testParametricCatalogClampsExtremeMemoryThreshold() {
        // memoryPercent above 84 must keep memory.critical sane (≤99).
        let custom = SystemMonitorAlertThresholds(
            cpuPercent: 85,
            memoryPercent: 90,
            temperatureCelsius: 85,
            batteryPercent: 20,
            diskFreeGB: 10,
            networkMBps: 30
        )
        let rules = SystemMonitorAlertRuleCatalog.rules(for: custom)
        let memoryCritical = rules.first(where: { $0.id == "memory.critical" })

        XCTAssertEqual(memoryCritical?.threshold, 99)
    }

    func testThresholdsSettingClampsValuesToAllowedRange() {
        let base = SystemMonitorAlertThresholds.default

        // CPU upper-bound clamp.
        XCTAssertEqual(base.setting(150, for: .cpu).cpuPercent, SystemMonitorAlertThresholds.cpuPercentRange.upperBound)
        // Battery lower-bound clamp.
        XCTAssertEqual(
            base.setting(0, for: .battery).batteryPercent,
            SystemMonitorAlertThresholds.batteryPercentRange.lowerBound
        )
        // In-range values pass through untouched.
        XCTAssertEqual(base.setting(70, for: .cpu).cpuPercent, 70)
    }

    // MARK: - Severity palette

    @MainActor
    func testAlertVisualsExposeDistinctColorPerSeverity() {
        let info = SystemMonitorAlertVisuals.color(for: .info)
        let warn = SystemMonitorAlertVisuals.color(for: .warn)
        let critical = SystemMonitorAlertVisuals.color(for: .critical)

        XCTAssertNotEqual(info, warn)
        XCTAssertNotEqual(warn, critical)
        XCTAssertNotEqual(info, critical)
    }

    func testEngineUpdateRulesReflectsNewThresholdsOnNextProcess() {
        let clock = MutableClock(start: Date(timeIntervalSince1970: 0))
        let initialThresholds = SystemMonitorAlertThresholds.default
        let engine = SystemMonitorAlertEngine(
            rules: SystemMonitorAlertRuleCatalog.rules(for: initialThresholds),
            clock: clock
        )

        // 75% CPU stays under the default 85% threshold even after sustaining.
        clock.advance(by: 10)
        XCTAssertTrue(engine.process(snapshot: snapshot(cpuUsage: 0.75)).isEmpty)
        XCTAssertTrue(engine.currentAlerts.isEmpty)

        // User lowers the CPU threshold to 50%; rebuild rules.
        let lowered = initialThresholds.setting(50, for: .cpu)
        engine.updateRules(SystemMonitorAlertRuleCatalog.rules(for: lowered))

        // Sustain window for cpu.warn is 5s; advance and re-feed the same value.
        _ = engine.process(snapshot: snapshot(cpuUsage: 0.75))
        clock.advance(by: 5)
        let changes = engine.process(snapshot: snapshot(cpuUsage: 0.75))
        guard case .fired(let alert)? = changes.first else {
            XCTFail("CPU rule should fire after the threshold is lowered below the current value")
            return
        }
        XCTAssertEqual(alert.metric, .cpu)
    }

    // MARK: - Helpers

    private func snapshot(
        cpuUsage: Double? = nil,
        memoryPressure: Double? = nil,
        memoryUsage: Double? = nil,
        downloadBytesPerSecond: Double? = nil,
        uploadBytesPerSecond: Double? = nil,
        temperatureCelsius: Double? = nil,
        diskFreeBytes: Int64? = nil,
        batteryPercent: Double? = nil
    ) -> SystemMonitorSnapshot {
        SystemMonitorSnapshot(
            cpuUsage: cpuUsage,
            memoryPressure: memoryPressure,
            memoryUsage: memoryUsage,
            downloadBytesPerSecond: downloadBytesPerSecond,
            uploadBytesPerSecond: uploadBytesPerSecond,
            temperatureCelsius: temperatureCelsius,
            diskFreeBytes: diskFreeBytes,
            batteryPercent: batteryPercent,
            blocks: SystemMonitorSnapshot.unavailable.blocks
        )
    }
}

private final class MutableClock: SystemMonitorClock, @unchecked Sendable {
    private var current: Date

    init(start: Date) {
        self.current = start
    }

    func now() -> Date {
        current
    }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
