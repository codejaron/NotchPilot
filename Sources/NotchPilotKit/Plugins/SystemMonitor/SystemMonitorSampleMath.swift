import Darwin
import Foundation

enum SystemMonitorSampleMath {
    static let minimumRateInterval: TimeInterval = 0.1

    static func cpuUsage(from previous: SystemMonitorCPUTicks?, to current: SystemMonitorCPUTicks?) -> Double? {
        guard let previous, let current else {
            return nil
        }

        guard current.total >= previous.total,
              current.active >= previous.active
        else {
            return nil
        }

        let totalDelta = current.total - previous.total
        guard totalDelta > 0 else {
            return nil
        }

        let activeDelta = current.active - previous.active
        return clamp(Double(activeDelta) / Double(totalDelta))
    }

    static func memoryUsage(counters: SystemMonitorMemoryCounters?, physicalMemoryBytes: UInt64) -> Double? {
        guard let counters, physicalMemoryBytes > 0 else {
            return nil
        }

        return clamp(Double(counters.usedBytes) / Double(physicalMemoryBytes))
    }

    static func memoryPressure(rawPercent: Int32?) -> Double? {
        guard let rawPercent else {
            return nil
        }

        return clamp(1 - Double(rawPercent) / 100)
    }

    static func bytesPerSecond(previous: UInt64?, current: UInt64?, interval: TimeInterval?) -> Double? {
        guard let previous,
              let current,
              let interval,
              interval >= minimumRateInterval,
              current >= previous
        else {
            return nil
        }

        return Double(current - previous) / interval
    }

    static func processActivities(
        previous: [pid_t: SystemMonitorProcessCounter],
        current: [SystemMonitorProcessCounter],
        interval: TimeInterval?,
        processorCount: Int
    ) -> [SystemMonitorProcessActivity] {
        let safeProcessorCount = max(1, processorCount)

        let perProcessActivities = current.map { counter in
            let previousCounter = previous[counter.pid]
            let cpuPercent = Self.processCPUPercent(
                previousNanoseconds: previousCounter?.cpuTimeNanoseconds,
                currentNanoseconds: counter.cpuTimeNanoseconds,
                interval: interval,
                processorCount: safeProcessorCount
            )
            let diskRate = Self.bytesPerSecond(
                previous: previousCounter?.diskBytes,
                current: counter.diskBytes,
                interval: interval
            )

            return ProcessRate(
                groupName: counter.groupName,
                cpuPercent: cpuPercent,
                memoryBytes: counter.memoryBytes,
                diskBytesPerSecond: diskRate
            )
        }

        let groupedActivities = Dictionary(grouping: perProcessActivities, by: \.groupName)
        return groupedActivities.keys.sorted().map { groupName in
            let group = groupedActivities[groupName] ?? []
            let cpuValues = group.compactMap(\.cpuPercent)
            let diskValues = group.compactMap(\.diskBytesPerSecond)

            return SystemMonitorProcessActivity(
                id: groupName,
                name: groupName,
                cpuPercent: cpuValues.isEmpty ? nil : cpuValues.reduce(0, +),
                memoryBytes: group.reduce(0) { total, activity in
                    Self.addClamped(total, activity.memoryBytes)
                },
                diskBytesPerSecond: diskValues.isEmpty ? nil : diskValues.reduce(0, +)
            )
        }
    }

    static func networkProcessActivities(
        previous: [String: SystemMonitorNetworkProcessCounter],
        current: [SystemMonitorNetworkProcessCounter],
        interval: TimeInterval?
    ) -> [SystemMonitorNetworkProcessActivity] {
        current.compactMap { counter in
            guard let previousCounter = previous[counter.key],
                  let interval,
                  interval >= minimumRateInterval
            else {
                return nil
            }

            let receivedRate = bytesPerSecond(
                previous: previousCounter.receivedBytes,
                current: counter.receivedBytes,
                interval: interval
            ) ?? 0
            let sentRate = bytesPerSecond(
                previous: previousCounter.sentBytes,
                current: counter.sentBytes,
                interval: interval
            ) ?? 0

            guard receivedRate + sentRate > 0 else {
                return nil
            }

            return SystemMonitorNetworkProcessActivity(
                key: counter.key,
                name: counter.name,
                downloadBytesPerSecond: receivedRate,
                uploadBytesPerSecond: sentRate
            )
        }
    }

    private static func processCPUPercent(
        previousNanoseconds: UInt64?,
        currentNanoseconds: UInt64?,
        interval: TimeInterval?,
        processorCount: Int
    ) -> Double? {
        guard let previousNanoseconds,
              let currentNanoseconds,
              let interval,
              interval >= minimumRateInterval,
              currentNanoseconds >= previousNanoseconds
        else {
            return nil
        }

        let nanosecondsPerSecond = 1_000_000_000.0
        let rawPercent = Double(currentNanoseconds - previousNanoseconds) / (interval * nanosecondsPerSecond) * 100
        let maximumPercent = Double(max(1, processorCount)) * 100
        return min(max(0, rawPercent), maximumPercent)
    }

    private struct ProcessRate {
        let groupName: String
        let cpuPercent: Double?
        let memoryBytes: Int64
        let diskBytesPerSecond: Double?
    }

    private static func addClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else {
            return lhs
        }

        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }

    static func addClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
