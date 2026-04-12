import Foundation

enum SystemMonitorMetric: String, CaseIterable, Equatable, Hashable, Sendable {
    case cpu
    case memory
    case network
    case disk
    case temperature
    case battery

    var title: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "MEMORY"
        case .network:
            return "NETWORK"
        case .disk:
            return "DISK"
        case .temperature:
            return "TEMP"
        case .battery:
            return "BATTERY"
        }
    }
}

struct SystemMonitorSneakConfiguration: Equatable, Sendable {
    static let defaultLimit = 2
    static let `default` = SystemMonitorSneakConfiguration(
        left: [.cpu, .memory],
        right: [.network, .temperature]
    )

    let leftMetrics: [SystemMonitorMetric]
    let rightMetrics: [SystemMonitorMetric]

    init(
        left: [SystemMonitorMetric],
        right: [SystemMonitorMetric],
        limit: Int = defaultLimit
    ) {
        leftMetrics = Array(left.prefix(limit))
        rightMetrics = Array(right.prefix(limit))
    }
}

struct SystemMonitorTopItem: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let value: String

    init(id: String? = nil, name: String, value: String) {
        self.name = name
        self.value = value
        self.id = id ?? "\(name)-\(value)"
    }
}

struct SystemMonitorSneakNetworkRow: Equatable, Sendable {
    let symbolSystemName: String
    let value: String
}

struct SystemMonitorBlockSnapshot: Equatable, Identifiable, Sendable {
    static let topItemLimit = 5

    let kind: SystemMonitorMetric
    let title: String
    let summary: String
    let detail: String
    let topItems: [SystemMonitorTopItem]

    var id: SystemMonitorMetric { kind }

    init(
        kind: SystemMonitorMetric,
        title: String,
        summary: String,
        detail: String,
        topItems: [SystemMonitorTopItem]
    ) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.detail = detail
        self.topItems = Array(topItems.prefix(Self.topItemLimit))
    }
}

struct SystemMonitorSnapshot: Equatable, Sendable {
    let cpuUsage: Double?
    let memoryPressure: Double?
    let memoryUsage: Double?
    let downloadBytesPerSecond: Double?
    let uploadBytesPerSecond: Double?
    let temperatureCelsius: Double?
    let diskFreeBytes: Int64?
    let batteryPercent: Double?
    let blocks: [SystemMonitorBlockSnapshot]

    init(
        cpuUsage: Double?,
        memoryPressure: Double? = nil,
        memoryUsage: Double?,
        downloadBytesPerSecond: Double?,
        uploadBytesPerSecond: Double?,
        temperatureCelsius: Double?,
        diskFreeBytes: Int64?,
        batteryPercent: Double?,
        blocks: [SystemMonitorBlockSnapshot]
    ) {
        self.cpuUsage = cpuUsage
        self.memoryPressure = memoryPressure
        self.memoryUsage = memoryUsage
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.temperatureCelsius = temperatureCelsius
        self.diskFreeBytes = diskFreeBytes
        self.batteryPercent = batteryPercent
        self.blocks = blocks
    }

    var cpuText: String { SystemMonitorFormat.percent(cpuUsage) }
    var memoryText: String { memoryPressureText }
    var memoryPressureText: String { SystemMonitorFormat.percent(memoryPressure) }
    var memoryUsageText: String { SystemMonitorFormat.percent(memoryUsage) }
    var downloadText: String { SystemMonitorFormat.compactByteRate(downloadBytesPerSecond) }
    var uploadText: String { SystemMonitorFormat.compactByteRate(uploadBytesPerSecond) }
    var temperatureText: String { SystemMonitorFormat.temperature(temperatureCelsius) }
    var batteryText: String { SystemMonitorFormat.percent(batteryPercent) }
    var compactNetworkRows: [SystemMonitorSneakNetworkRow] {
        [
            SystemMonitorSneakNetworkRow(symbolSystemName: "arrow.up.right", value: uploadText),
            SystemMonitorSneakNetworkRow(symbolSystemName: "arrow.down.left", value: downloadText),
        ]
    }

    static let unavailable = SystemMonitorSnapshot(
        cpuUsage: nil,
        memoryPressure: nil,
        memoryUsage: nil,
        downloadBytesPerSecond: nil,
        uploadBytesPerSecond: nil,
        temperatureCelsius: nil,
        diskFreeBytes: nil,
        batteryPercent: nil,
        blocks: [
            SystemMonitorBlockSnapshot(kind: .cpu, title: "CPU", summary: "--", detail: "", topItems: []),
            SystemMonitorBlockFactory.memoryBlock(
                memoryPressure: nil,
                memoryUsage: nil,
                topItems: []
            ),
            SystemMonitorBlockFactory.networkBlock(
                downloadBytesPerSecond: nil,
                uploadBytesPerSecond: nil,
                topItems: []
            ),
            SystemMonitorBlockFactory.diskStatusBlock(
                diskFreeBytes: nil,
                temperatureCelsius: nil,
                batteryPercent: nil
            ),
        ]
    )
}

enum SystemMonitorBlockFactory {
    static let networkTopItemCount = 3

    static func memoryBlock(
        memoryPressure: Double?,
        memoryUsage: Double?,
        topItems: [SystemMonitorTopItem]
    ) -> SystemMonitorBlockSnapshot {
        SystemMonitorBlockSnapshot(
            kind: .memory,
            title: "MEMORY",
            summary: SystemMonitorFormat.percent(memoryPressure),
            detail: SystemMonitorFormat.memoryStatusDetail(
                pressure: memoryPressure,
                memoryUsage: memoryUsage
            ),
            topItems: topItems
        )
    }

    static func networkBlock(
        downloadBytesPerSecond: Double?,
        uploadBytesPerSecond: Double?,
        topItems: [SystemMonitorTopItem]
    ) -> SystemMonitorBlockSnapshot {
        SystemMonitorBlockSnapshot(
            kind: .network,
            title: "NETWORK",
            summary: SystemMonitorFormat.directionalByteRate(
                downloadBytesPerSecond: downloadBytesPerSecond ?? 0,
                uploadBytesPerSecond: uploadBytesPerSecond ?? 0
            ),
            detail: "",
            topItems: paddedNetworkTopItems(topItems)
        )
    }

    static func diskStatusBlock(
        diskFreeBytes: Int64?,
        temperatureCelsius: Double?,
        batteryPercent: Double?
    ) -> SystemMonitorBlockSnapshot {
        SystemMonitorBlockSnapshot(
            kind: .disk,
            title: "SYSTEM",
            summary: SystemMonitorFormat.diskFree(diskFreeBytes),
            detail: "",
            topItems: [
                SystemMonitorTopItem(
                    id: "system-temperature",
                    name: "Temperature",
                    value: SystemMonitorFormat.temperature(temperatureCelsius)
                ),
                SystemMonitorTopItem(
                    id: "system-battery",
                    name: "Battery",
                    value: SystemMonitorFormat.percent(batteryPercent)
                ),
            ]
        )
    }

    private static func paddedNetworkTopItems(_ topItems: [SystemMonitorTopItem]) -> [SystemMonitorTopItem] {
        let visibleItems = Array(topItems.prefix(networkTopItemCount))
        guard visibleItems.count < networkTopItemCount else {
            return visibleItems
        }

        let placeholders = (visibleItems.count..<networkTopItemCount).map { index in
            SystemMonitorTopItem(
                id: "network-placeholder-\(index)",
                name: "—",
                value: SystemMonitorFormat.directionalByteRate(
                    downloadBytesPerSecond: 0,
                    uploadBytesPerSecond: 0
                )
            )
        }
        return visibleItems + placeholders
    }
}

enum SystemMonitorFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return "\(Int((value * 100).rounded()))%"
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return "\(Int(value.rounded()))°"
    }

    static func byteRate(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        if value >= 1_000_000 {
            return String(format: "%.1f MB/s", value / 1_000_000)
        }

        return String(format: "%.0f KB/s", value / 1_000)
    }

    static func compactByteRate(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }

        return String(format: "%.0f KB/s", value / 1_000)
    }

    static func directionalByteRate(
        downloadBytesPerSecond: Double?,
        uploadBytesPerSecond: Double?
    ) -> String {
        "↓\(byteRate(downloadBytesPerSecond)) ↑\(byteRate(uploadBytesPerSecond))"
    }

    static func diskFree(_ value: Int64?) -> String {
        guard let value else {
            return "--"
        }

        return String(format: "%.1f GB", Double(value) / 1_000_000_000)
    }

    static func memoryStatusDetail(pressure: Double?, memoryUsage: Double?) -> String {
        "Pressure \(percent(pressure)) · Memory \(percent(memoryUsage))"
    }

    static func storage(_ value: Int64) -> String {
        let absoluteValue = Double(value)
        if absoluteValue >= 1_000_000_000 {
            return String(format: "%.1f GB", absoluteValue / 1_000_000_000)
        }
        if absoluteValue >= 1_000_000 {
            return String(format: "%.0f MB", absoluteValue / 1_000_000)
        }
        return String(format: "%.0f KB", absoluteValue / 1_000)
    }
}
