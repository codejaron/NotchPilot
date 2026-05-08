import AppKit
import Darwin
import Foundation
import IOKit.ps
import SystemConfiguration

struct SystemMonitorSamplingDemand: Sendable, Equatable {
    let includesPerProcessNetwork: Bool

    init(includesPerProcessNetwork: Bool = false) {
        self.includesPerProcessNetwork = includesPerProcessNetwork
    }

    static let basic = SystemMonitorSamplingDemand(includesPerProcessNetwork: false)
    static let detailed = SystemMonitorSamplingDemand(includesPerProcessNetwork: true)
}

protocol SystemMonitorSampling: Sendable {
    func snapshot() -> SystemMonitorSnapshot
    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot
}

extension SystemMonitorSampling {
    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot {
        snapshot()
    }
}

struct SystemMonitorUnavailableSampler: SystemMonitorSampling {
    init() {}

    func snapshot() -> SystemMonitorSnapshot {
        .unavailable
    }
}

struct SystemMonitorStaticSampler: SystemMonitorSampling {
    let storedSnapshot: SystemMonitorSnapshot

    init(snapshot: SystemMonitorSnapshot) {
        self.storedSnapshot = snapshot
    }

    func snapshot() -> SystemMonitorSnapshot {
        storedSnapshot
    }
}

struct SystemMonitorDefaultSampler: SystemMonitorSampling {
    private let collector: @Sendable () -> SystemMonitorSnapshot?
    private let fallback: any SystemMonitorSampling

    init(fallback: any SystemMonitorSampling = SystemMonitorUnavailableSampler()) {
        let bestEffortSampler = SystemMonitorBestEffortSampler()
        self.init(
            collector: {
                bestEffortSampler.snapshot()
            },
            fallback: fallback
        )
    }

    init(
        collector: @escaping @Sendable () -> SystemMonitorSnapshot?,
        fallback: any SystemMonitorSampling = SystemMonitorUnavailableSampler()
    ) {
        self.collector = collector
        self.fallback = fallback
    }

    func snapshot() -> SystemMonitorSnapshot {
        collector() ?? fallback.snapshot()
    }
}

struct SystemMonitorCPUTicks: Equatable, Sendable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var active: UInt64 { user + system }
    var total: UInt64 { user + system + idle + nice }
}

struct SystemMonitorMemoryCounters: Equatable, Sendable {
    let freeBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let speculativeBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let purgeableBytes: UInt64
    let externalBytes: UInt64

    init(
        freeBytes: UInt64 = 0,
        activeBytes: UInt64,
        inactiveBytes: UInt64,
        speculativeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        purgeableBytes: UInt64,
        externalBytes: UInt64
    ) {
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.speculativeBytes = speculativeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.purgeableBytes = purgeableBytes
        self.externalBytes = externalBytes
    }

    var usedBytes: UInt64 {
        let grossUsed = activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes
        let reclaimable = purgeableBytes + externalBytes
        return grossUsed > reclaimable ? grossUsed - reclaimable : 0
    }
}

struct SystemMonitorProcessCounter: Equatable, Sendable {
    let pid: pid_t
    let name: String
    let groupName: String
    let cpuTimeNanoseconds: UInt64?
    let memoryBytes: Int64
    let diskBytes: UInt64?

    init(
        pid: pid_t,
        name: String,
        groupName: String? = nil,
        cpuTimeNanoseconds: UInt64?,
        memoryBytes: Int64,
        diskBytes: UInt64?
    ) {
        self.pid = pid
        self.name = name
        self.groupName = groupName ?? name
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.memoryBytes = memoryBytes
        self.diskBytes = diskBytes
    }
}

struct SystemMonitorProcessActivity: Equatable, Sendable {
    let id: String
    let name: String
    let cpuPercent: Double?
    let memoryBytes: Int64
    let diskBytesPerSecond: Double?
}

struct SystemMonitorNetworkProcessCounter: Equatable, Sendable {
    let key: String
    let name: String
    let receivedBytes: UInt64
    let sentBytes: UInt64

    var totalBytes: UInt64 {
        receivedBytes + sentBytes
    }
}

struct SystemMonitorNetworkProcessActivity: Equatable, Sendable {
    let key: String
    let name: String
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double

    var totalBytesPerSecond: Double {
        downloadBytesPerSecond + uploadBytesPerSecond
    }
}

struct SystemMonitorCPUProcessRow: Equatable, Sendable {
    let pid: pid_t
    let command: String
    let cpuPercent: Double
}

struct SystemMonitorMemoryProcessRow: Equatable, Sendable {
    let pid: pid_t
    let command: String
    let memoryBytes: Int64
}

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

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

final class SystemMonitorBestEffortSampler: SystemMonitorSampling, @unchecked Sendable {
    private struct NetworkCounter {
        let receivedBytes: UInt64
        let sentBytes: UInt64
        let date: Date
    }

    private struct ProcessRusage {
        let cpuTimeNanoseconds: UInt64
        let physicalFootprintBytes: UInt64
        let diskBytes: UInt64
    }

    private var previousSystemCPUTicks: SystemMonitorCPUTicks?
    private var previousProcessCounters: [pid_t: SystemMonitorProcessCounter] = [:]
    private var previousProcessDate: Date?
    private var previousNetworkCounter: NetworkCounter?
    private var previousNetworkProcessCounters: [String: SystemMonitorNetworkProcessCounter] = [:]
    private var previousNetworkProcessDate: Date?
    private var cachedNetworkProcessActivities: [SystemMonitorNetworkProcessActivity] = []
    private var applicationDisplayNameCache: [String: String] = [:]
    private let sensorBridge: SystemMonitorSMCSensorBridge

    init(sensorBridge: SystemMonitorSMCSensorBridge = SystemMonitorSMCSensorBridge()) {
        self.sensorBridge = sensorBridge
    }

    func snapshot() -> SystemMonitorSnapshot {
        snapshot(demand: .basic)
    }

    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot {
        let date = Date()
        let currentCPUTicks = systemCPUTicks()
        let cpuUsage = SystemMonitorSampleMath.cpuUsage(from: previousSystemCPUTicks, to: currentCPUTicks)
        if let currentCPUTicks {
            previousSystemCPUTicks = currentCPUTicks
        }

        let memoryCounters = memoryCounters()
        let totalMemoryBytes = physicalMemoryBytes()
        let memoryUsage = SystemMonitorSampleMath.memoryUsage(
            counters: memoryCounters,
            physicalMemoryBytes: totalMemoryBytes
        )
        let memoryPressure = SystemMonitorSampleMath.memoryPressure(
            rawPercent: memorystatusFreePercent()
        )

        let processInterval = previousProcessDate.map { date.timeIntervalSince($0) }
        let processCounters = processCounters()
        let processActivities = SystemMonitorSampleMath.processActivities(
            previous: previousProcessCounters,
            current: processCounters,
            interval: processInterval,
            processorCount: ProcessInfo.processInfo.activeProcessorCount
        )
        let statsCPUTopItems = statsCPUTopItems()
        previousProcessCounters = processCounters.reduce(into: [:]) { result, counter in
            result[counter.pid] = counter
        }
        previousProcessDate = date

        let networkRates = networkByteRates()
        let networkProcessActivities = refreshNetworkProcessActivitiesIfNeeded(
            demand: demand,
            date: date
        )

        let diskFreeBytes = diskFreeBytes()
        let batteryPercent = batteryPercent()
        let temperatureCelsius = sensorBridge.cpuTemperatureCelsius()

        return SystemMonitorSnapshot(
            cpuUsage: cpuUsage,
            memoryPressure: memoryPressure,
            memoryUsage: memoryUsage,
            downloadBytesPerSecond: networkRates.download,
            uploadBytesPerSecond: networkRates.upload,
            temperatureCelsius: temperatureCelsius,
            diskFreeBytes: diskFreeBytes,
            batteryPercent: batteryPercent,
            blocks: blocks(
                cpuUsage: cpuUsage,
                memoryPressure: memoryPressure,
                memoryUsage: memoryUsage,
                downloadBytesPerSecond: networkRates.download,
                uploadBytesPerSecond: networkRates.upload,
                temperatureCelsius: temperatureCelsius,
                diskFreeBytes: diskFreeBytes,
                batteryPercent: batteryPercent,
                statsCPUTopItems: statsCPUTopItems,
                processActivities: processActivities,
                networkProcessActivities: networkProcessActivities
            )
        )
    }

    private func refreshNetworkProcessActivitiesIfNeeded(
        demand: SystemMonitorSamplingDemand,
        date: Date
    ) -> [SystemMonitorNetworkProcessActivity] {
        guard demand.includesPerProcessNetwork else {
            return cachedNetworkProcessActivities
        }

        let interval = previousNetworkProcessDate.map { date.timeIntervalSince($0) }
        let currentCounters = networkProcessCounters()
        let activities = SystemMonitorSampleMath.networkProcessActivities(
            previous: previousNetworkProcessCounters,
            current: currentCounters,
            interval: interval
        )
        previousNetworkProcessCounters = currentCounters.reduce(into: [:]) { result, counter in
            result[counter.key] = counter
        }
        previousNetworkProcessDate = date
        cachedNetworkProcessActivities = activities
        return activities
    }

    private func systemCPUTicks() -> SystemMonitorCPUTicks? {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        guard result == KERN_SUCCESS, let processorInfo else {
            return nil
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: processorInfo),
                vm_size_t(Int(processorInfoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for index in 0..<Int(processorCount) {
            let cpuInfo = processorInfo.advanced(by: index * Int(CPU_STATE_MAX))
            user += UInt64(cpuInfo[Int(CPU_STATE_USER)])
            system += UInt64(cpuInfo[Int(CPU_STATE_SYSTEM)])
            idle += UInt64(cpuInfo[Int(CPU_STATE_IDLE)])
            nice += UInt64(cpuInfo[Int(CPU_STATE_NICE)])
        }

        return SystemMonitorCPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private func memoryCounters() -> SystemMonitorMemoryCounters? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { statisticsPointer in
            statisticsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }

        var pageSize = vm_size_t()
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return nil
        }
        let pageSizeBytes = UInt64(pageSize)

        return SystemMonitorMemoryCounters(
            freeBytes: UInt64(statistics.free_count) * pageSizeBytes,
            activeBytes: UInt64(statistics.active_count) * pageSizeBytes,
            inactiveBytes: UInt64(statistics.inactive_count) * pageSizeBytes,
            speculativeBytes: UInt64(statistics.speculative_count) * pageSizeBytes,
            wiredBytes: UInt64(statistics.wire_count) * pageSizeBytes,
            compressedBytes: UInt64(statistics.compressor_page_count) * pageSizeBytes,
            purgeableBytes: UInt64(statistics.purgeable_count) * pageSizeBytes,
            externalBytes: UInt64(statistics.external_page_count) * pageSizeBytes
        )
    }

    private func physicalMemoryBytes() -> UInt64 {
        var info = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_info(mach_host_self(), HOST_BASIC_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS, info.max_mem > 0 else {
            return ProcessInfo.processInfo.physicalMemory
        }

        return UInt64(info.max_mem)
    }

    private func memorystatusFreePercent() -> Int32? {
        var level: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        let result = sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0)
        guard result == 0 else {
            return nil
        }
        return Int32(level)
    }

    static func memoryPressure(fromMemoryPressureOutput output: String) -> Double? {
        guard let freeRange = output.range(
            of: #"System-wide memory free percentage:\s*([0-9]+(?:\.[0-9]+)?)%"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let match = String(output[freeRange])
        let digits = match.filter { $0.isNumber || $0 == "." }
        guard let freePercent = Double(digits) else {
            return nil
        }

        return min(1, max(0, 1 - (freePercent / 100)))
    }

    private func processCounters() -> [SystemMonitorProcessCounter] {
        processIDs().compactMap(processCounter)
    }

    private func statsCPUTopItems() -> [SystemMonitorTopItem] {
        guard let output = runProcess(
            executable: "/bin/ps",
            arguments: ["-Aceo", "pid,pcpu,comm", "-r"]
        ) else {
            return []
        }

        let groupedRows = Dictionary(grouping: Self.cpuProcessRows(fromPSOutput: output)) { row in
            processDisplayName(pid: row.pid, command: row.command)
        }

        return groupedRows
            .map { name, rows in
                (name: name, cpuPercent: rows.reduce(0) { $0 + $1.cpuPercent })
            }
            .sorted { lhs, rhs in lhs.cpuPercent > rhs.cpuPercent }
            .prefix(SystemMonitorBlockFactory.cpuTopItemCount)
            .map { row in
                SystemMonitorTopItem(
                    id: "\(row.name)-stats-cpu",
                    name: row.name,
                    value: "\(Int(row.cpuPercent.rounded()))%"
                )
            }
    }

    static func cpuProcessRows(fromPSOutput output: String) -> [SystemMonitorCPUProcessRow] {
        output
            .components(separatedBy: .newlines)
            .dropFirst()
            .compactMap { line in
                let columns = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard columns.count == 3,
                      let pid = pid_t(String(columns[0])),
                      let cpuPercent = Double(String(columns[1]).replacingOccurrences(of: ",", with: "."))
                else {
                    return nil
                }

                return SystemMonitorCPUProcessRow(
                    pid: pid,
                    command: String(columns[2]).trimmingCharacters(in: .whitespacesAndNewlines),
                    cpuPercent: cpuPercent
                )
            }
    }

    static func memoryProcessRows(fromTopOutput output: String) -> [SystemMonitorMemoryProcessRow] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let columns = trimmedLine.split(separator: " ", omittingEmptySubsequences: true)
                guard columns.count >= 3,
                      let pid = pid_t(String(columns[0])),
                      let memoryBytes = memoryBytes(fromTopToken: String(columns[columns.count - 1]))
                else {
                    return nil
                }

                let command = columns
                    .dropFirst()
                    .dropLast()
                    .joined(separator: " ")

                return SystemMonitorMemoryProcessRow(
                    pid: pid,
                    command: command,
                    memoryBytes: memoryBytes
                )
            }
    }

    static func memoryBytes(fromTopToken token: String) -> Int64? {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unit = normalizedToken.last else {
            return nil
        }

        let numericString = normalizedToken.dropLast().filter { $0.isNumber || $0 == "." }
        guard var value = Double(numericString) else {
            return nil
        }

        switch unit {
        case "G":
            value *= 1_024
        case "M":
            break
        case "K":
            value /= 1_024
        default:
            guard unit.isNumber, let bytes = Int64(normalizedToken) else {
                return nil
            }
            return bytes
        }

        return Int64(value * 1_000_000)
    }

    private func processIDs() -> [pid_t] {
        let maximumProcessCount = 8_192
        var pids = [pid_t](repeating: 0, count: maximumProcessCount)
        let bytes = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.stride)
        )
        guard bytes > 0 else {
            return []
        }

        let count = min(pids.count, Int(bytes) / MemoryLayout<pid_t>.stride)
        return pids.prefix(count).filter { $0 > 0 }
    }

    private func processCounter(pid: pid_t) -> SystemMonitorProcessCounter? {
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        let taskInfoResult = withUnsafeMutablePointer(to: &taskInfo) { taskInfoPointer in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, taskInfoPointer, taskInfoSize)
        }
        guard taskInfoResult == taskInfoSize else {
            return nil
        }

        let rusage = processRusage(pid: pid)
        let identity = processIdentity(pid: pid)
        return SystemMonitorProcessCounter(
            pid: pid,
            name: identity.name,
            groupName: identity.groupName,
            cpuTimeNanoseconds: rusage?.cpuTimeNanoseconds,
            memoryBytes: rusage.map { Self.int64Clamped($0.physicalFootprintBytes) }
                ?? Self.int64Clamped(taskInfo.pti_resident_size),
            diskBytes: rusage?.diskBytes
        )
    }

    private func processRusage(pid: pid_t) -> ProcessRusage? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
            usagePointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, reboundPointer)
            }
        }
        guard result == 0 else {
            return nil
        }

        return ProcessRusage(
            cpuTimeNanoseconds: usage.ri_user_time + usage.ri_system_time,
            physicalFootprintBytes: usage.ri_phys_footprint,
            diskBytes: usage.ri_diskio_bytesread + usage.ri_diskio_byteswritten
        )
    }

    private func processIdentity(pid: pid_t) -> (name: String, groupName: String) {
        if let path = processPath(pid: pid) {
            let processName = URL(fileURLWithPath: path).lastPathComponent
            let fallbackName = processName.isEmpty ? "pid \(pid)" : processName
            let groupName = Self.applicationGroupName(
                fromProcessPath: path,
                bundleDisplayName: applicationDisplayName(forApplicationBundlePath:)
            ) ?? fallbackName

            return (fallbackName, groupName)
        }

        let fallbackName = procName(pid: pid) ?? "pid \(pid)"
        return (fallbackName, fallbackName)
    }

    private func processDisplayName(pid: pid_t, command: String) -> String {
        let identity = processIdentity(pid: pid)
        if identity.groupName.hasPrefix("pid ") == false {
            return identity.groupName
        }

        if command.contains("com.apple.Virtua"), command.contains("Docker") {
            return "Docker"
        }

        if command.hasPrefix("/") {
            if let appName = Self.applicationGroupName(
                fromProcessPath: command,
                bundleDisplayName: applicationDisplayName(forApplicationBundlePath:)
            ) {
                return appName
            }

            let lastPathComponent = URL(fileURLWithPath: command).lastPathComponent
            if lastPathComponent.isEmpty == false {
                return lastPathComponent
            }
        }

        return command.isEmpty ? "pid \(pid)" : command
    }

    private func processPath(pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else {
            return nil
        }

        let path = Self.string(fromNullTerminatedBuffer: pathBuffer)
        return path.isEmpty ? nil : path
    }

    private func procName(pid: pid_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else {
            return nil
        }

        let name = Self.string(fromNullTerminatedBuffer: nameBuffer)
        return name.isEmpty ? nil : name
    }

    static func applicationGroupName(
        fromProcessPath processPath: String,
        bundleDisplayName: (String) -> String?
    ) -> String? {
        let pathComponents = URL(fileURLWithPath: processPath).pathComponents
        guard let appIndex = pathComponents.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }

        let bundlePath = NSString.path(withComponents: Array(pathComponents.prefix(appIndex + 1)))
        return bundleDisplayName(bundlePath) ?? defaultApplicationName(fromApplicationBundlePath: bundlePath)
    }

    private func applicationDisplayName(forApplicationBundlePath bundlePath: String) -> String? {
        if let cachedName = applicationDisplayNameCache[bundlePath] {
            return cachedName
        }

        let bundle = Bundle(path: bundlePath)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? Self.defaultApplicationName(fromApplicationBundlePath: bundlePath)
        applicationDisplayNameCache[bundlePath] = displayName
        return displayName
    }

    private static func defaultApplicationName(fromApplicationBundlePath bundlePath: String) -> String {
        URL(fileURLWithPath: bundlePath)
            .deletingPathExtension()
            .lastPathComponent
    }

    private func networkByteRates() -> (download: Double?, upload: Double?) {
        guard let currentCounter = networkCounter() else {
            return (nil, nil)
        }

        defer {
            previousNetworkCounter = currentCounter
        }

        let interval = previousNetworkCounter.map {
            currentCounter.date.timeIntervalSince($0.date)
        }

        return (
            SystemMonitorSampleMath.bytesPerSecond(
                previous: previousNetworkCounter?.receivedBytes,
                current: currentCounter.receivedBytes,
                interval: interval
            ),
            SystemMonitorSampleMath.bytesPerSecond(
                previous: previousNetworkCounter?.sentBytes,
                current: currentCounter.sentBytes,
                interval: interval
            )
        )
    }

    private func networkCounter() -> NetworkCounter? {
        let primaryInterfaceName = primaryNetworkInterfaceName()
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return nil
        }
        defer {
            freeifaddrs(interfaces)
        }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = interfaces

        while let current = pointer {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let interfaceName = String(cString: interface.ifa_name)
            let matchesPrimaryInterface = primaryInterfaceName.map { $0 == interfaceName } ?? true

            if isUp,
               isLoopback == false,
               matchesPrimaryInterface,
               let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                receivedBytes += UInt64(networkData.ifi_ibytes)
                sentBytes += UInt64(networkData.ifi_obytes)
            }

            pointer = interface.ifa_next
        }

        return NetworkCounter(receivedBytes: receivedBytes, sentBytes: sentBytes, date: Date())
    }

    private func primaryNetworkInterfaceName() -> String? {
        guard let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let interfaceName = global["PrimaryInterface"] as? String,
              interfaceName.isEmpty == false
        else {
            return nil
        }

        return interfaceName
    }

    private func networkProcessCounters() -> [SystemMonitorNetworkProcessCounter] {
        guard let output = runProcess(
            executable: "/usr/bin/nettop",
            arguments: ["-P", "-L", "1", "-n", "-x", "-t", "external", "-J", "bytes_in,bytes_out"]
        ) else {
            return []
        }

        return Self.networkProcessCounters(fromNettopCSV: output)
    }

    static func networkProcessCounters(fromNettopCSV output: String) -> [SystemMonitorNetworkProcessCounter] {
        output
            .components(separatedBy: .newlines)
            .dropFirst()
            .compactMap { line in
                let columns = line
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard columns.count >= 3,
                      columns[0].isEmpty == false,
                      let receivedBytes = UInt64(columns[1]),
                      let sentBytes = UInt64(columns[2])
                else {
                    return nil
                }

                return SystemMonitorNetworkProcessCounter(
                    key: columns[0],
                    name: displayName(fromNettopIdentifier: columns[0]),
                    receivedBytes: receivedBytes,
                    sentBytes: sentBytes
                )
            }
    }

    static func displayName(fromNettopIdentifier identifier: String) -> String {
        let parts = identifier.split(separator: ".")
        guard let last = parts.last,
              parts.count > 1,
              last.allSatisfy(\.isNumber)
        else {
            return identifier
        }

        return parts.dropLast().joined(separator: ".")
    }

    private func diskFreeBytes() -> Int64? {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity > 0 {
                return capacity
            }
        } catch {
            // Fall back to FileManager below.
        }

        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return freeSize.int64Value
            }
        } catch {
            return nil
        }
        return nil
    }

    private func batteryPercent() -> Double? {
        batteryPercentFromIOKit()
    }

    private func batteryPercentFromIOKit() -> Double? {
        let powerSourcesInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo).takeRetainedValue() as [CFTypeRef]

        for powerSource in powerSources {
            guard let description = IOPSGetPowerSourceDescription(powerSourcesInfo, powerSource)
                .takeUnretainedValue() as? [String: Any],
                let percent = Self.batteryPercent(fromPowerSourceDescription: description)
            else {
                continue
            }

            return percent
        }

        return nil
    }

    static func batteryPercent(fromPowerSourceDescription description: [String: Any]) -> Double? {
        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int
            ?? description["Current Capacity"] as? Int
        let maximumCapacity = description[kIOPSMaxCapacityKey] as? Int
            ?? description["Max Capacity"] as? Int
            ?? 100

        guard let currentCapacity,
              maximumCapacity > 0,
              currentCapacity >= 0
        else {
            return nil
        }

        return min(1, Double(currentCapacity) / Double(maximumCapacity))
    }

    static func batteryPercent(fromPMSetOutput output: String) -> Double? {
        let percentToken = output
            .split(whereSeparator: \.isWhitespace)
            .first { token in
                token.contains("%")
            }

        guard let percentToken else {
            return nil
        }

        let digits = percentToken.filter(\.isNumber)
        guard let value = Double(digits), value >= 0 else {
            return nil
        }

        return min(1, value / 100)
    }

    private func runProcess(executable: String, arguments: [String], timeout: TimeInterval = 2) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let watchdog = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
            process.waitUntilExit()
            watchdog.cancel()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func blocks(
        cpuUsage: Double?,
        memoryPressure: Double?,
        memoryUsage: Double?,
        downloadBytesPerSecond: Double?,
        uploadBytesPerSecond: Double?,
        temperatureCelsius: Double?,
        diskFreeBytes: Int64?,
        batteryPercent: Double?,
        statsCPUTopItems: [SystemMonitorTopItem],
        processActivities: [SystemMonitorProcessActivity],
        networkProcessActivities: [SystemMonitorNetworkProcessActivity]
    ) -> [SystemMonitorBlockSnapshot] {
        let fallbackTopCPU = processActivities
            .compactMap { activity -> (SystemMonitorProcessActivity, Double)? in
                guard let cpuPercent = activity.cpuPercent, cpuPercent > 0.01 else {
                    return nil
                }
                return (activity, cpuPercent)
            }
            .sorted { lhs, rhs in lhs.1 > rhs.1 }
            .prefix(SystemMonitorBlockFactory.cpuTopItemCount)
            .map { activity, cpuPercent in
                SystemMonitorTopItem(
                    id: "\(activity.id)-cpu",
                    name: activity.name,
                    value: "\(Int(cpuPercent.rounded()))%"
                )
            }
        let topCPU = statsCPUTopItems.isEmpty ? fallbackTopCPU : statsCPUTopItems

        let topMemory = processActivities
            .filter { $0.memoryBytes > 0 }
            .sorted { lhs, rhs in lhs.memoryBytes > rhs.memoryBytes }
            .prefix(SystemMonitorBlockSnapshot.defaultTopItemLimit)
            .map { activity in
                SystemMonitorTopItem(
                    id: "\(activity.id)-memory",
                    name: activity.name,
                    value: SystemMonitorFormat.storage(activity.memoryBytes)
                )
            }

        let topNetwork = networkProcessActivities
            .sorted { lhs, rhs in lhs.totalBytesPerSecond > rhs.totalBytesPerSecond }
            .prefix(SystemMonitorBlockFactory.networkTopItemCount)
            .map { activity in
                let directionalRate = SystemMonitorFormat.directionalRateText(
                    downloadBytesPerSecond: activity.downloadBytesPerSecond,
                    uploadBytesPerSecond: activity.uploadBytesPerSecond
                )
                return SystemMonitorTopItem(
                    id: "\(activity.key)-network",
                    name: activity.name,
                    value: directionalRate.upload,
                    secondaryValue: directionalRate.download
                )
            }

        return [
            SystemMonitorBlockFactory.cpuBlock(
                usage: cpuUsage,
                topItems: topCPU
            ),
            SystemMonitorBlockFactory.memoryBlock(
                memoryPressure: memoryPressure,
                memoryUsage: memoryUsage,
                topItems: topMemory
            ),
            SystemMonitorBlockFactory.networkBlock(
                downloadBytesPerSecond: downloadBytesPerSecond,
                uploadBytesPerSecond: uploadBytesPerSecond,
                topItems: topNetwork
            ),
            SystemMonitorBlockFactory.diskStatusBlock(
                diskFreeBytes: diskFreeBytes,
                temperatureCelsius: temperatureCelsius,
                batteryPercent: batteryPercent
            ),
        ]
    }

    private static func int64Clamped(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }

    private static func string(fromNullTerminatedBuffer buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
