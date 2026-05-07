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

enum SystemMonitorSneakMode: String, Equatable, Sendable, Codable, CaseIterable {
    /// Always show the configured left/right slots regardless of system state.
    case alwaysOn
    /// Show the configured left/right slots and additionally surface reactive
    /// metrics that crossed an alert threshold.
    case pinnedReactive
    /// Hide the sneak preview entirely until any reactive metric fires; clear
    /// the preview when nothing is firing.
    case ambient
}

struct SystemMonitorSneakConfiguration: Equatable, Sendable {
    static let defaultLimit = 2
    static let `default` = SystemMonitorSneakConfiguration(
        mode: .pinnedReactive,
        left: [.cpu],
        right: [.network],
        reactive: [.memory, .temperature, .battery, .disk]
    )

    let mode: SystemMonitorSneakMode
    let leftMetrics: [SystemMonitorMetric]
    let rightMetrics: [SystemMonitorMetric]
    /// Metrics allowed to surface in the sneak preview when their alert rule
    /// fires. Pinned metrics are filtered out automatically because they are
    /// already on screen.
    let reactiveMetrics: [SystemMonitorMetric]

    init(
        mode: SystemMonitorSneakMode = .pinnedReactive,
        left: [SystemMonitorMetric],
        right: [SystemMonitorMetric],
        reactive: [SystemMonitorMetric] = SystemMonitorMetric.allCases,
        limit: Int = defaultLimit
    ) {
        self.mode = mode
        let trimmedLeft = Array(left.prefix(limit))
        let trimmedRight = Array(right.prefix(limit))
        leftMetrics = trimmedLeft
        rightMetrics = trimmedRight

        let pinned = Set(trimmedLeft + trimmedRight)
        var seen: Set<SystemMonitorMetric> = []
        reactiveMetrics = reactive.filter { metric in
            guard pinned.contains(metric) == false else { return false }
            return seen.insert(metric).inserted
        }
    }

    /// Pinned metrics in their stable left-to-right ordering; useful when a
    /// caller does not care about the slot split.
    var pinnedMetrics: [SystemMonitorMetric] {
        leftMetrics + rightMetrics
    }
}

/// Pure helpers used by the settings UI to mutate one pinned slot at a time
/// without disturbing the surrounding slots.
enum SystemMonitorSneakSlotEditor {
    /// Replaces the metric at `index` in a length-2 sparse slot view of
    /// `metrics`, returning the dense array suitable for persistence.
    ///
    /// Behaviour:
    /// - Setting `nil` clears that slot. Other slots stay untouched.
    /// - Setting a metric that already lives in another slot vacates that
    ///   other slot, so a metric appears at most once per side.
    /// - Indexes outside the configuration's `defaultLimit` are ignored and
    ///   the metrics array is returned trimmed to the limit.
    static func metrics(
        byUpdating metrics: [SystemMonitorMetric],
        setting metric: SystemMonitorMetric?,
        at index: Int
    ) -> [SystemMonitorMetric] {
        let limit = SystemMonitorSneakConfiguration.defaultLimit

        var slots: [SystemMonitorMetric?] = Array(repeating: nil, count: limit)
        for (slotIndex, slotMetric) in metrics.prefix(limit).enumerated() {
            slots[slotIndex] = slotMetric
        }

        guard slots.indices.contains(index) else {
            return Array(metrics.prefix(limit))
        }

        if let metric {
            for otherIndex in slots.indices where otherIndex != index && slots[otherIndex] == metric {
                slots[otherIndex] = nil
            }
        }

        slots[index] = metric

        return slots.compactMap { $0 }
    }
}

struct SystemMonitorTopItem: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let value: String
    let secondaryValue: String?

    init(id: String? = nil, name: String, value: String, secondaryValue: String? = nil) {
        self.name = name
        self.value = value
        self.secondaryValue = secondaryValue
        let identityValue = secondaryValue.map { "\(value)-\($0)" } ?? value
        self.id = id ?? "\(name)-\(identityValue)"
    }
}

struct SystemMonitorDirectionalRateText: Equatable, Sendable {
    let upload: String
    let download: String
}

struct SystemMonitorSneakNetworkRow: Equatable, Sendable {
    let symbolSystemName: String
    let value: String
}

struct SystemMonitorBlockSnapshot: Equatable, Identifiable, Sendable {
    static let defaultTopItemLimit = 5

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
        topItems: [SystemMonitorTopItem],
        topItemLimit: Int = Self.defaultTopItemLimit
    ) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.detail = detail
        self.topItems = Array(topItems.prefix(topItemLimit))
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
    var directionalRateText: SystemMonitorDirectionalRateText {
        SystemMonitorFormat.directionalRateText(
            downloadBytesPerSecond: downloadBytesPerSecond,
            uploadBytesPerSecond: uploadBytesPerSecond
        )
    }
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
            SystemMonitorBlockFactory.cpuBlock(usage: nil, topItems: []),
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
    static let cpuTopItemCount = 6
    static let networkTopItemCount = 3

    static func cpuBlock(
        usage: Double?,
        topItems: [SystemMonitorTopItem]
    ) -> SystemMonitorBlockSnapshot {
        SystemMonitorBlockSnapshot(
            kind: .cpu,
            title: "CPU",
            summary: SystemMonitorFormat.percent(usage),
            detail: "",
            topItems: topItems,
            topItemLimit: cpuTopItemCount
        )
    }

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
            summary: "",
            detail: "",
            topItems: [
                SystemMonitorTopItem(
                    id: "system-disk-free",
                    name: "Disk Free",
                    value: SystemMonitorFormat.diskFree(diskFreeBytes)
                ),
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
            let directionalRate = SystemMonitorFormat.directionalRateText(
                downloadBytesPerSecond: 0,
                uploadBytesPerSecond: 0
            )
            return SystemMonitorTopItem(
                id: "network-placeholder-\(index)",
                name: "—",
                value: directionalRate.upload,
                secondaryValue: directionalRate.download
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
            return String(format: "%.1fMB/s", value / 1_000_000)
        }

        return String(format: "%.0f KB/s", value / 1_000)
    }

    static func directionalRateText(
        downloadBytesPerSecond: Double?,
        uploadBytesPerSecond: Double?
    ) -> SystemMonitorDirectionalRateText {
        SystemMonitorDirectionalRateText(
            upload: byteRate(uploadBytesPerSecond),
            download: byteRate(downloadBytesPerSecond)
        )
    }

    static func directionalByteRate(
        downloadBytesPerSecond: Double?,
        uploadBytesPerSecond: Double?
    ) -> String {
        let directionalRate = directionalRateText(
            downloadBytesPerSecond: downloadBytesPerSecond,
            uploadBytesPerSecond: uploadBytesPerSecond
        )
        return "↑\(directionalRate.upload) ↓\(directionalRate.download)"
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
