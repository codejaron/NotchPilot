import Darwin
import Foundation

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

struct SystemMonitorNetworkByteCounter: Equatable, Sendable {
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let date: Date
}

struct SystemMonitorNetworkByteRates: Equatable, Sendable {
    let download: Double?
    let upload: Double?

    static let unavailable = SystemMonitorNetworkByteRates(download: nil, upload: nil)
}

struct SystemMonitorNetworkRateTracker: Sendable {
    private var previousCounter: SystemMonitorNetworkByteCounter?
    private var cachedRates = SystemMonitorNetworkByteRates.unavailable

    mutating func rates(for currentCounter: SystemMonitorNetworkByteCounter?) -> SystemMonitorNetworkByteRates {
        guard let currentCounter else {
            previousCounter = nil
            cachedRates = .unavailable
            return .unavailable
        }

        guard let previousCounter else {
            self.previousCounter = currentCounter
            return cachedRates
        }

        guard currentCounter.receivedBytes >= previousCounter.receivedBytes,
              currentCounter.sentBytes >= previousCounter.sentBytes
        else {
            self.previousCounter = currentCounter
            cachedRates = .unavailable
            return .unavailable
        }

        let interval = currentCounter.date.timeIntervalSince(previousCounter.date)
        guard interval >= SystemMonitorSampleMath.minimumRateInterval else {
            return cachedRates
        }

        let rates = SystemMonitorNetworkByteRates(
            download: SystemMonitorSampleMath.bytesPerSecond(
                previous: previousCounter.receivedBytes,
                current: currentCounter.receivedBytes,
                interval: interval
            ),
            upload: SystemMonitorSampleMath.bytesPerSecond(
                previous: previousCounter.sentBytes,
                current: currentCounter.sentBytes,
                interval: interval
            )
        )
        self.previousCounter = currentCounter
        cachedRates = rates
        return rates
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
