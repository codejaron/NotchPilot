import AppKit
import Darwin
import Foundation
import IOKit.ps
import SystemConfiguration

final class SystemMonitorBestEffortSampler: SystemMonitorSampling, SystemMonitorAsyncSampling, @unchecked Sendable {
    private struct ProcessRusage {
        let cpuTimeNanoseconds: UInt64
        let physicalFootprintBytes: UInt64
        let diskBytes: UInt64
    }

    private struct SystemMetrics {
        let cpuUsage: Double?
        let memoryPressure: Double?
        let memoryUsage: Double?
        let networkRates: SystemMonitorNetworkByteRates
        let diskFreeBytes: Int64?
        let batteryPercent: Double?
        let temperatureCelsius: Double?
    }

    private struct ProcessDetails {
        let activities: [SystemMonitorProcessActivity]
        let statsTopItems: [SystemMonitorTopItem]
    }

    private var previousSystemCPUTicks: SystemMonitorCPUTicks?
    private var previousProcessCounters: [pid_t: SystemMonitorProcessCounter] = [:]
    private var previousProcessDate: Date?
    private var networkRateTracker = SystemMonitorNetworkRateTracker()
    private var previousNetworkProcessCounters: [String: SystemMonitorNetworkProcessCounter] = [:]
    private var previousNetworkProcessDate: Date?
    private var cachedNetworkProcessActivities: [SystemMonitorNetworkProcessActivity] = []
    private var applicationDisplayNameCache: [String: String] = [:]
    private var networkProcessNameCache: [String: String] = [:]
    private let sensorBridge: SystemMonitorSMCSensorBridge

    init(sensorBridge: SystemMonitorSMCSensorBridge = SystemMonitorSMCSensorBridge()) {
        self.sensorBridge = sensorBridge
    }

    func snapshot() -> SystemMonitorSnapshot {
        snapshot(demand: .basic)
    }

    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot {
        let date = Date()
        let metrics = systemMetrics()
        let statsTopItems = demand.includesProcessDetails ? statsCPUTopItems() : []
        let processDetails = processDetails(demand: demand, date: date, statsTopItems: statsTopItems)
        let networkProcessActivities = refreshNetworkProcessActivitiesIfNeeded(
            demand: demand,
            date: date
        )

        return makeSnapshot(
            metrics: metrics,
            processDetails: processDetails,
            networkProcessActivities: networkProcessActivities
        )
    }

    func snapshotAsync(demand: SystemMonitorSamplingDemand) async -> SystemMonitorSnapshot {
        let date = Date()
        let metrics = systemMetrics()
        let statsTopItems = demand.includesProcessDetails ? await statsCPUTopItemsAsync() : []
        let processDetails = processDetails(demand: demand, date: date, statsTopItems: statsTopItems)
        let networkProcessActivities = await refreshNetworkProcessActivitiesIfNeededAsync(
            demand: demand,
            date: date
        )

        return makeSnapshot(
            metrics: metrics,
            processDetails: processDetails,
            networkProcessActivities: networkProcessActivities
        )
    }

    private func systemMetrics() -> SystemMetrics {
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

        return SystemMetrics(
            cpuUsage: cpuUsage,
            memoryPressure: memoryPressure,
            memoryUsage: memoryUsage,
            networkRates: networkByteRates(),
            diskFreeBytes: diskFreeBytes(),
            batteryPercent: batteryPercent(),
            temperatureCelsius: sensorBridge.cpuTemperatureCelsius()
        )
    }

    private func processDetails(
        demand: SystemMonitorSamplingDemand,
        date: Date,
        statsTopItems: [SystemMonitorTopItem]
    ) -> ProcessDetails {
        if demand.includesProcessDetails {
            let processInterval = previousProcessDate.map { date.timeIntervalSince($0) }
            let processCounters = processCounters()
            let processActivities = SystemMonitorSampleMath.processActivities(
                previous: previousProcessCounters,
                current: processCounters,
                interval: processInterval,
                processorCount: ProcessInfo.processInfo.activeProcessorCount
            )
            previousProcessCounters = processCounters.reduce(into: [:]) { result, counter in
                result[counter.pid] = counter
            }
            previousProcessDate = date
            return ProcessDetails(activities: processActivities, statsTopItems: statsTopItems)
        } else {
            previousProcessCounters.removeAll()
            previousProcessDate = nil
            return ProcessDetails(activities: [], statsTopItems: [])
        }
    }

    private func makeSnapshot(
        metrics: SystemMetrics,
        processDetails: ProcessDetails,
        networkProcessActivities: [SystemMonitorNetworkProcessActivity]
    ) -> SystemMonitorSnapshot {
        return SystemMonitorSnapshot(
            cpuUsage: metrics.cpuUsage,
            memoryPressure: metrics.memoryPressure,
            memoryUsage: metrics.memoryUsage,
            downloadBytesPerSecond: metrics.networkRates.download,
            uploadBytesPerSecond: metrics.networkRates.upload,
            temperatureCelsius: metrics.temperatureCelsius,
            diskFreeBytes: metrics.diskFreeBytes,
            batteryPercent: metrics.batteryPercent,
            blocks: blocks(
                cpuUsage: metrics.cpuUsage,
                memoryPressure: metrics.memoryPressure,
                memoryUsage: metrics.memoryUsage,
                downloadBytesPerSecond: metrics.networkRates.download,
                uploadBytesPerSecond: metrics.networkRates.upload,
                temperatureCelsius: metrics.temperatureCelsius,
                diskFreeBytes: metrics.diskFreeBytes,
                batteryPercent: metrics.batteryPercent,
                statsCPUTopItems: processDetails.statsTopItems,
                processActivities: processDetails.activities,
                networkProcessActivities: networkProcessActivities
            )
        )
    }

    private func refreshNetworkProcessActivitiesIfNeeded(
        demand: SystemMonitorSamplingDemand,
        date: Date
    ) -> [SystemMonitorNetworkProcessActivity] {
        guard demand.includesPerProcessNetwork else {
            return resetNetworkProcessActivities()
        }

        return updateNetworkProcessActivities(date: date, currentCounters: networkProcessCounters())
    }

    private func refreshNetworkProcessActivitiesIfNeededAsync(
        demand: SystemMonitorSamplingDemand,
        date: Date
    ) async -> [SystemMonitorNetworkProcessActivity] {
        guard demand.includesPerProcessNetwork else {
            return resetNetworkProcessActivities()
        }

        return updateNetworkProcessActivities(date: date, currentCounters: await networkProcessCountersAsync())
    }

    private func resetNetworkProcessActivities() -> [SystemMonitorNetworkProcessActivity] {
        previousNetworkProcessCounters.removeAll()
        previousNetworkProcessDate = nil
        cachedNetworkProcessActivities = []
        return []
    }

    private func updateNetworkProcessActivities(
        date: Date,
        currentCounters: [SystemMonitorNetworkProcessCounter]
    ) -> [SystemMonitorNetworkProcessActivity] {
        let interval = previousNetworkProcessDate.map { date.timeIntervalSince($0) }
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

        return statsCPUTopItems(fromPSOutput: output)
    }

    private func statsCPUTopItemsAsync() async -> [SystemMonitorTopItem] {
        guard let output = await runProcessAsync(
            executable: "/bin/ps",
            arguments: ["-Aceo", "pid,pcpu,comm", "-r"]
        ) else {
            return []
        }

        return statsCPUTopItems(fromPSOutput: output)
    }

    private func statsCPUTopItems(fromPSOutput output: String) -> [SystemMonitorTopItem] {
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
            cpuTimeNanoseconds: SystemMonitorSampleMath.addClamped(
                usage.ri_user_time,
                usage.ri_system_time
            ),
            physicalFootprintBytes: usage.ri_phys_footprint,
            diskBytes: SystemMonitorSampleMath.addClamped(
                usage.ri_diskio_bytesread,
                usage.ri_diskio_byteswritten
            )
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

    private func networkByteRates() -> SystemMonitorNetworkByteRates {
        networkRateTracker.rates(for: networkCounter())
    }

    private func networkCounter() -> SystemMonitorNetworkByteCounter? {
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

        return SystemMonitorNetworkByteCounter(receivedBytes: receivedBytes, sentBytes: sentBytes, date: Date())
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
            arguments: ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
        ) else {
            return []
        }

        return networkProcessCounters(fromNettopOutput: output)
    }

    private func networkProcessCountersAsync() async -> [SystemMonitorNetworkProcessCounter] {
        guard let output = await runProcessAsync(
            executable: "/usr/bin/nettop",
            arguments: ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
        ) else {
            return []
        }

        return networkProcessCounters(fromNettopOutput: output)
    }

    private func networkProcessCounters(fromNettopOutput output: String) -> [SystemMonitorNetworkProcessCounter] {
        let parsed = Self.networkProcessCounters(fromNettopCSV: output)
        let resolved = parsed.map { counter -> SystemMonitorNetworkProcessCounter in
            guard let resolvedName = resolvedNetworkProcessName(forNettopIdentifier: counter.key),
                  resolvedName != counter.name
            else {
                return counter
            }
            return SystemMonitorNetworkProcessCounter(
                key: counter.key,
                name: resolvedName,
                receivedBytes: counter.receivedBytes,
                sentBytes: counter.sentBytes
            )
        }

        let liveIdentifiers = Set(resolved.map(\.key))
        networkProcessNameCache = networkProcessNameCache.filter { liveIdentifiers.contains($0.key) }

        return resolved
    }

    private func resolvedNetworkProcessName(forNettopIdentifier identifier: String) -> String? {
        if let cached = networkProcessNameCache[identifier] {
            return cached.isEmpty ? nil : cached
        }

        guard let pid = Self.pid(fromNettopIdentifier: identifier) else {
            networkProcessNameCache[identifier] = ""
            return nil
        }

        guard let path = processPath(pid: pid) else {
            networkProcessNameCache[identifier] = ""
            return nil
        }

        let resolved = Self.resolvedDisplayName(
            fromProcessPath: path,
            bundleDisplayName: { [unowned self] bundlePath in
                self.applicationDisplayName(forApplicationBundlePath: bundlePath)
            }
        )
        networkProcessNameCache[identifier] = resolved ?? ""
        return resolved
    }

    static func pid(fromNettopIdentifier identifier: String) -> pid_t? {
        guard let separatorIndex = identifier.lastIndex(of: ".") else {
            return nil
        }
        let pidString = identifier[identifier.index(after: separatorIndex)...]
        guard pidString.isEmpty == false,
              pidString.allSatisfy(\.isNumber)
        else {
            return nil
        }
        return pid_t(pidString)
    }

    static func resolvedDisplayName(
        fromProcessPath processPath: String,
        bundleDisplayName: (String) -> String?
    ) -> String? {
        let pathComponents = URL(fileURLWithPath: processPath).pathComponents
        if let appIndex = pathComponents.lastIndex(where: { $0.hasSuffix(".app") }) {
            let bundlePath = NSString.path(withComponents: Array(pathComponents.prefix(appIndex + 1)))
            if let bundleName = bundleDisplayName(bundlePath), bundleName.isEmpty == false {
                return bundleName
            }
        }

        let executable = URL(fileURLWithPath: processPath).lastPathComponent
        return executable.isEmpty ? nil : executable
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
        guard let output = ProcessOutputCapture.run(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            timeout: timeout
        ), output.terminationStatus == 0 else {
            return nil
        }

        return String(data: output.standardOutput, encoding: .utf8)
    }

    private func runProcessAsync(executable: String, arguments: [String], timeout: TimeInterval = 2) async -> String? {
        guard let output = await ProcessOutputCapture.runAsync(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            timeout: timeout
        ), output.terminationStatus == 0 else {
            return nil
        }

        return String(data: output.standardOutput, encoding: .utf8)
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
