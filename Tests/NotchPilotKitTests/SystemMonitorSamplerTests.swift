import XCTest
@testable import NotchPilotKit

final class SystemMonitorSamplerTests: XCTestCase {
    func testUnavailableSamplerReturnsPlaceholderSnapshot() {
        let sampler = SystemMonitorUnavailableSampler()

        let snapshot = sampler.snapshot()

        XCTAssertEqual(snapshot, .unavailable)
        XCTAssertEqual(snapshot.blocks.count, 4)
    }

    func testDefaultSamplerUsesFallbackWhenCollectorReturnsNil() {
        let fallbackSnapshot = SystemMonitorSnapshot(
            cpuUsage: 0.22,
            memoryUsage: 0.37,
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 2_000,
            temperatureCelsius: 48,
            diskFreeBytes: 49_000_000_000,
            batteryPercent: 0.84,
            blocks: []
        )
        let sampler = SystemMonitorDefaultSampler(
            collector: { nil },
            fallback: SystemMonitorStaticSampler(snapshot: fallbackSnapshot)
        )

        XCTAssertEqual(sampler.snapshot(), fallbackSnapshot)
    }

    func testDefaultSamplerUsesCollectorSnapshotWhenAvailable() {
        let collectedSnapshot = SystemMonitorSnapshot(
            cpuUsage: 0.64,
            memoryUsage: 0.51,
            downloadBytesPerSecond: 4_200_000,
            uploadBytesPerSecond: 900_000,
            temperatureCelsius: 62,
            diskFreeBytes: 12_000_000_000,
            batteryPercent: nil,
            blocks: [
                SystemMonitorBlockSnapshot(kind: .cpu, title: "CPU", summary: "64%", detail: "load", topItems: [])
            ]
        )
        let sampler = SystemMonitorDefaultSampler(
            collector: { collectedSnapshot },
            fallback: SystemMonitorUnavailableSampler()
        )

        XCTAssertEqual(sampler.snapshot(), collectedSnapshot)
    }

    func testBatteryPercentParsesPMSetOutput() {
        let output = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=1234567)	84%; discharging; 5:02 remaining present: true
        """

        XCTAssertEqual(SystemMonitorBestEffortSampler.batteryPercent(fromPMSetOutput: output), 0.84)
    }

    func testMemoryPressureParsesAppleQueryOutputIntoPressurePercentage() throws {
        let output = """
        The system has 17179869184 (1048576 pages with a page size of 16384).
        System-wide memory free percentage: 46%
        """

        let pressure = try XCTUnwrap(
            SystemMonitorBestEffortSampler.memoryPressure(fromMemoryPressureOutput: output)
        )

        XCTAssertEqual(
            pressure,
            0.54,
            accuracy: 0.001
        )
    }

    func testBestEffortSamplerProducesRealMachineBackedSnapshot() {
        let sampler = SystemMonitorBestEffortSampler()

        _ = sampler.snapshot(demand: .detailed)
        Thread.sleep(forTimeInterval: 0.2)
        let snapshot = sampler.snapshot(demand: .detailed)

        XCTAssertEqual(snapshot.blocks.map(\.kind), [.cpu, .memory, .network, .disk])
        XCTAssertEqual(snapshot.blocks.first(where: { $0.kind == .network })?.topItems.count, 3)
        XCTAssertNotNil(snapshot.memoryUsage)
        XCTAssertNotNil(snapshot.diskFreeBytes)
        if let temperatureCelsius = snapshot.temperatureCelsius {
            XCTAssertGreaterThan(temperatureCelsius, 0)
            XCTAssertLessThan(temperatureCelsius, 121)
        }
    }

    func testBestEffortSamplerUsesMemoryPressureAsMemorySummaryAndLabelsBothValues() {
        let sampler = SystemMonitorBestEffortSampler()

        let snapshot = sampler.snapshot()
        let memoryBlock = try? XCTUnwrap(snapshot.blocks.first(where: { $0.kind == .memory }))

        XCTAssertNotNil(memoryBlock)
        XCTAssertTrue(memoryBlock?.detail.hasPrefix("Pressure \(memoryBlock?.summary ?? "")") == true)
        XCTAssertTrue(memoryBlock?.detail.contains("Memory ") == true)
    }

    func testMemoryPressureMapsKernelFreePercentToOneMinusFraction() throws {
        let pressure = try XCTUnwrap(
            SystemMonitorSampleMath.memoryPressure(rawPercent: 40)
        )

        XCTAssertEqual(pressure, 0.6, accuracy: 0.001)
    }

    func testMemoryPressureIsUnavailableWithoutRawPercent() {
        XCTAssertNil(SystemMonitorSampleMath.memoryPressure(rawPercent: nil))
    }

    func testMemoryPressureClampsOutOfRangeRawPercents() throws {
        let high = try XCTUnwrap(SystemMonitorSampleMath.memoryPressure(rawPercent: 150))
        let low = try XCTUnwrap(SystemMonitorSampleMath.memoryPressure(rawPercent: -10))

        XCTAssertEqual(high, 0)
        XCTAssertEqual(low, 1)
    }

    func testBasicSamplingDemandSkipsPerProcessNetworkCollection() {
        let sampler = SystemMonitorBestEffortSampler()

        _ = sampler.snapshot(demand: .basic)
        Thread.sleep(forTimeInterval: 0.2)
        let snapshot = sampler.snapshot(demand: .basic)

        let networkBlock = snapshot.blocks.first { $0.kind == .network }
        let nonPlaceholderCount = networkBlock?.topItems.filter { $0.id.hasPrefix("network-placeholder-") == false }.count
        XCTAssertEqual(nonPlaceholderCount, 0)
    }

    func testCPUUsageUsesMachTickDeltas() {
        let previous = SystemMonitorCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = SystemMonitorCPUTicks(user: 200, system: 100, idle: 950, nice: 0)

        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorSampleMath.cpuUsage(from: previous, to: current)),
            0.6,
            accuracy: 0.001
        )
    }

    func testCPUUsageMatchesStatsByExcludingNiceTicksFromActiveUsage() {
        let previous = SystemMonitorCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = SystemMonitorCPUTicks(user: 200, system: 100, idle: 950, nice: 100)

        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorSampleMath.cpuUsage(from: previous, to: current)),
            150.0 / 350.0,
            accuracy: 0.001
        )
    }

    func testCPUUsageIsUnavailableWithoutPreviousSample() {
        let current = SystemMonitorCPUTicks(user: 200, system: 100, idle: 950, nice: 0)

        XCTAssertNil(SystemMonitorSampleMath.cpuUsage(from: nil, to: current))
    }

    func testMemoryUsageUsesRealMemoryCounters() {
        let counters = SystemMonitorMemoryCounters(
            activeBytes: 100,
            inactiveBytes: 40,
            speculativeBytes: 20,
            wiredBytes: 50,
            compressedBytes: 25,
            purgeableBytes: 15,
            externalBytes: 10
        )

        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorSampleMath.memoryUsage(counters: counters, physicalMemoryBytes: 1_000)),
            0.21,
            accuracy: 0.001
        )
    }

    func testBatteryPercentParsesIOPowerSourceDescription() {
        let description: [String: Any] = [
            "Current Capacity": 84,
            "Max Capacity": 100,
        ]

        XCTAssertEqual(SystemMonitorBestEffortSampler.batteryPercent(fromPowerSourceDescription: description), 0.84)
    }

    func testSMCFixedPointTemperatureDecodingMatchesStatsBridge() {
        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorSMCSensorBridge.decodedValue(dataType: "sp78", bytes: [0x25, 0x80])),
            37.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorSMCSensorBridge.decodedValue(dataType: "flt ", bytes: [0x00, 0x00, 0x20, 0x42])),
            40,
            accuracy: 0.001
        )
    }

    func testTemperatureBridgeFiltersInvalidSensorReadings() {
        XCTAssertNil(SystemMonitorSMCSensorBridge.averageTemperature(from: [0, 121, -1, 128]))
        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorSMCSensorBridge.averageTemperature(from: [36, 44, 128, 0])),
            40,
            accuracy: 0.001
        )
    }

    func testByteRateRequiresRealPreviousCounter() {
        XCTAssertNil(SystemMonitorSampleMath.bytesPerSecond(previous: nil, current: 1_000, interval: 1))
        XCTAssertNil(SystemMonitorSampleMath.bytesPerSecond(previous: 1_000, current: 500, interval: 1))
        XCTAssertNil(SystemMonitorSampleMath.bytesPerSecond(previous: 1_000, current: 2_000, interval: 0.01))
        XCTAssertEqual(
            try XCTUnwrap(SystemMonitorSampleMath.bytesPerSecond(previous: 1_000, current: 2_500, interval: 1.5)),
            1_000,
            accuracy: 0.001
        )
    }

    func testProcessActivitiesUseProcCounterDeltas() {
        let previous = [
            pid_t(42): SystemMonitorProcessCounter(
                pid: 42,
                name: "Xcode",
                groupName: "Xcode",
                cpuTimeNanoseconds: 1_000_000_000,
                memoryBytes: 500_000_000,
                diskBytes: 1_000
            ),
        ]
        let current = [
            SystemMonitorProcessCounter(
                pid: 42,
                name: "Xcode",
                groupName: "Xcode",
                cpuTimeNanoseconds: 2_500_000_000,
                memoryBytes: 750_000_000,
                diskBytes: 7_000
            ),
        ]

        let activities = SystemMonitorSampleMath.processActivities(
            previous: previous,
            current: current,
            interval: 1,
            processorCount: 8
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(try XCTUnwrap(activities[0].cpuPercent), 150, accuracy: 0.001)
        XCTAssertEqual(activities[0].memoryBytes, 750_000_000)
        XCTAssertEqual(try XCTUnwrap(activities[0].diskBytesPerSecond), 6_000, accuracy: 0.001)
    }

    func testProcessActivitiesGroupApplicationHelpers() {
        let previous = [
            pid_t(42): SystemMonitorProcessCounter(
                pid: 42,
                name: "Xcode",
                groupName: "Xcode",
                cpuTimeNanoseconds: 1_000_000_000,
                memoryBytes: 500_000_000,
                diskBytes: 1_000
            ),
            pid_t(43): SystemMonitorProcessCounter(
                pid: 43,
                name: "lldb-rpc-server",
                groupName: "Xcode",
                cpuTimeNanoseconds: 2_000_000_000,
                memoryBytes: 3_000_000_000,
                diskBytes: 2_000
            ),
        ]
        let current = [
            SystemMonitorProcessCounter(
                pid: 42,
                name: "Xcode",
                groupName: "Xcode",
                cpuTimeNanoseconds: 2_000_000_000,
                memoryBytes: 600_000_000,
                diskBytes: 2_000
            ),
            SystemMonitorProcessCounter(
                pid: 43,
                name: "lldb-rpc-server",
                groupName: "Xcode",
                cpuTimeNanoseconds: 4_000_000_000,
                memoryBytes: 3_400_000_000,
                diskBytes: 5_000
            ),
        ]

        let activities = SystemMonitorSampleMath.processActivities(
            previous: previous,
            current: current,
            interval: 1,
            processorCount: 8
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].name, "Xcode")
        XCTAssertEqual(activities[0].memoryBytes, 4_000_000_000)
        XCTAssertEqual(try XCTUnwrap(activities[0].cpuPercent), 300, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(activities[0].diskBytesPerSecond), 4_000, accuracy: 0.001)
    }

    func testProcessActivitiesDoNotInventRatesOnFirstSample() {
        let current = [
            SystemMonitorProcessCounter(
                pid: 42,
                name: "Xcode",
                groupName: "Xcode",
                cpuTimeNanoseconds: 2_500_000_000,
                memoryBytes: 750_000_000,
                diskBytes: 7_000
            ),
        ]

        let activities = SystemMonitorSampleMath.processActivities(
            previous: [:],
            current: current,
            interval: nil,
            processorCount: 8
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertNil(activities[0].cpuPercent)
        XCTAssertEqual(activities[0].memoryBytes, 750_000_000)
        XCTAssertNil(activities[0].diskBytesPerSecond)
    }

    func testApplicationGroupNameUsesOuterAppBundleForHelpers() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/Current/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

        let groupName = SystemMonitorBestEffortSampler.applicationGroupName(
            fromProcessPath: path,
            bundleDisplayName: { bundlePath in
                XCTAssertEqual(bundlePath, "/Applications/Google Chrome.app")
                return "Google Chrome"
            }
        )

        XCTAssertEqual(groupName, "Google Chrome")
    }

    func testStatsStyleMemoryTokenParserUsesTopUnits() {
        XCTAssertEqual(SystemMonitorBestEffortSampler.memoryBytes(fromTopToken: "3551M"), 3_551_000_000)
        XCTAssertEqual(SystemMonitorBestEffortSampler.memoryBytes(fromTopToken: "1G"), 1_024_000_000)
        XCTAssertEqual(SystemMonitorBestEffortSampler.memoryBytes(fromTopToken: "512K"), 500_000)
    }

    func testStatsStyleCPUProcessParserReadsPSOutput() {
        let output = """
          PID  %CPU COMM
        20147  41.2 /Applications/Xcode.app/Contents/Developer/usr/bin/lldb-rpc-server
        3449   20.5 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper
        """

        let rows = SystemMonitorBestEffortSampler.cpuProcessRows(fromPSOutput: output)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].pid, 20_147)
        XCTAssertEqual(rows[0].cpuPercent, 41.2)
        XCTAssertEqual(rows[0].command, "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb-rpc-server")
    }

    func testStatsStyleMemoryProcessParserReadsTopOutput() {
        let output = """
        PID    COMMAND          MEM
        20147  lldb-rpc-server  3551M
        3449   Google Chrome He 589M
        """

        let rows = SystemMonitorBestEffortSampler.memoryProcessRows(fromTopOutput: output)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].pid, 20_147)
        XCTAssertEqual(rows[0].command, "lldb-rpc-server")
        XCTAssertEqual(rows[0].memoryBytes, 3_551_000_000)
    }

    func testNettopCSVParserUsesRealCountersAndDropsPidSuffixForDisplay() {
        let output = """
        ,bytes_in,bytes_out,
        mDNSResponder.451,1968056,1986022,
        Google Chrome H.1538,1251600,3430,
        malformed,not-a-number,3430,
        """

        let counters = SystemMonitorBestEffortSampler.networkProcessCounters(fromNettopCSV: output)

        XCTAssertEqual(counters.count, 2)
        XCTAssertEqual(counters[0].key, "mDNSResponder.451")
        XCTAssertEqual(counters[0].name, "mDNSResponder")
        XCTAssertEqual(counters[0].receivedBytes, 1_968_056)
        XCTAssertEqual(counters[0].sentBytes, 1_986_022)
        XCTAssertEqual(counters[1].name, "Google Chrome H")
    }

    func testPidExtractionFromNettopIdentifierKeepsDottedCommSegment() {
        XCTAssertEqual(
            SystemMonitorBestEffortSampler.pid(fromNettopIdentifier: "Google Chrome H.1538"),
            1538
        )
        XCTAssertEqual(
            SystemMonitorBestEffortSampler.pid(fromNettopIdentifier: "com.docker.backend.42"),
            42
        )
        XCTAssertEqual(
            SystemMonitorBestEffortSampler.pid(fromNettopIdentifier: "mDNSResponder.451"),
            451
        )
    }

    func testPidExtractionRejectsIdentifiersWithoutNumericPidSuffix() {
        XCTAssertNil(SystemMonitorBestEffortSampler.pid(fromNettopIdentifier: "no-dot-here"))
        XCTAssertNil(SystemMonitorBestEffortSampler.pid(fromNettopIdentifier: "trailing.dot."))
        XCTAssertNil(SystemMonitorBestEffortSampler.pid(fromNettopIdentifier: "Chrome.notapid"))
    }

    func testResolvedDisplayNamePrefersInnermostAppBundle() {
        let helperPath = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/Current/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        let bundleDisplayName: (String) -> String? = { bundlePath in
            switch bundlePath {
            case let path where path.hasSuffix("/Google Chrome Helper.app"):
                return "Google Chrome Helper"
            case let path where path.hasSuffix("/Google Chrome.app"):
                return "Google Chrome"
            default:
                return nil
            }
        }

        let resolved = SystemMonitorBestEffortSampler.resolvedDisplayName(
            fromProcessPath: helperPath,
            bundleDisplayName: bundleDisplayName
        )

        XCTAssertEqual(resolved, "Google Chrome Helper")
    }

    func testResolvedDisplayNameFallsBackToExecutableForNonAppProcesses() {
        let cliPath = "/usr/local/bin/verge-mihomo"
        let resolved = SystemMonitorBestEffortSampler.resolvedDisplayName(
            fromProcessPath: cliPath,
            bundleDisplayName: { _ in nil }
        )

        XCTAssertEqual(resolved, "verge-mihomo")
    }

    func testResolvedDisplayNameFallsBackToExecutableWhenBundleHasNoDisplayName() {
        let path = "/Applications/Mystery.app/Contents/MacOS/Mystery"
        let resolved = SystemMonitorBestEffortSampler.resolvedDisplayName(
            fromProcessPath: path,
            bundleDisplayName: { _ in nil }
        )

        XCTAssertEqual(resolved, "Mystery")
    }

    func testNetworkProcessActivitiesUseNettopCounterDeltas() {
        let previous = [
            "Google Chrome H.1538": SystemMonitorNetworkProcessCounter(
                key: "Google Chrome H.1538",
                name: "Google Chrome H",
                receivedBytes: 1_000,
                sentBytes: 200
            ),
        ]
        let current = [
            SystemMonitorNetworkProcessCounter(
                key: "Google Chrome H.1538",
                name: "Google Chrome H",
                receivedBytes: 5_000,
                sentBytes: 1_200
            ),
        ]

        let activities = SystemMonitorSampleMath.networkProcessActivities(
            previous: previous,
            current: current,
            interval: 2
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].name, "Google Chrome H")
        XCTAssertEqual(activities[0].downloadBytesPerSecond, 2_000, accuracy: 0.001)
        XCTAssertEqual(activities[0].uploadBytesPerSecond, 500, accuracy: 0.001)
        XCTAssertEqual(activities[0].totalBytesPerSecond, 2_500, accuracy: 0.001)
    }
}
