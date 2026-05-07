import XCTest
@testable import NotchPilotKit

final class SystemMonitorModelsTests: XCTestCase {
    func testDashboardTypographyOnlyRaisesRowNumericValuesToTwelve() {
        XCTAssertEqual(SystemMonitorDashboardTypography.rowNameFontSize, 11, accuracy: 0.1)
        XCTAssertEqual(SystemMonitorDashboardTypography.standardRowValueFontSize, 12, accuracy: 0.1)
        XCTAssertEqual(SystemMonitorDashboardTypography.networkRowValueFontSize, 12, accuracy: 0.1)
        XCTAssertEqual(SystemMonitorDashboardTypography.systemStatusRowValueFontSize, 12, accuracy: 0.1)
        XCTAssertFalse(SystemMonitorDashboardTypography.systemStatusUsesMonospacedRowValues)
        XCTAssertEqual(SystemMonitorDashboardTypography.standardSummaryFontSize, 18, accuracy: 0.1)
        XCTAssertEqual(SystemMonitorDashboardTypography.networkSummaryFontSize, 13, accuracy: 0.1)
    }

    func testSneakConfigurationCapsEachSideAtTwoMetrics() {
        let configuration = SystemMonitorSneakConfiguration(
            left: [.cpu, .memory, .disk],
            right: [.network, .temperature, .battery]
        )

        XCTAssertEqual(configuration.leftMetrics, [.cpu, .memory])
        XCTAssertEqual(configuration.rightMetrics, [.network, .temperature])
    }

    func testDefaultSneakConfigurationMatchesApprovedLayout() {
        let configuration = SystemMonitorSneakConfiguration.default

        XCTAssertEqual(configuration.mode, .pinnedReactive)
        XCTAssertEqual(configuration.leftMetrics, [.cpu])
        XCTAssertEqual(configuration.rightMetrics, [.network])
        XCTAssertEqual(
            configuration.reactiveMetrics,
            [.memory, .temperature, .battery, .disk]
        )
    }

    func testReactiveMetricsExcludePinnedMetricsAutomatically() {
        let configuration = SystemMonitorSneakConfiguration(
            mode: .pinnedReactive,
            left: [.cpu, .memory],
            right: [.network],
            reactive: [.cpu, .memory, .temperature, .battery]
        )

        XCTAssertEqual(configuration.reactiveMetrics, [.temperature, .battery])
    }

    // MARK: - Slot editor regression coverage

    /// Reproduces the user-reported bug: when slot 1 holds `.cpu` and slot 2
    /// is hidden, replacing slot 1 with `.temperature` must leave slot 2
    /// hidden instead of pushing `.cpu` into it.
    func testSlotEditorReplacesSlotInPlaceWhenOtherSlotIsHidden() {
        let result = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu],
            setting: .temperature,
            at: 0
        )

        XCTAssertEqual(result, [.temperature])
    }

    func testSlotEditorReplacesFirstSlotWhenSecondSlotHasMetric() {
        let result = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu, .memory],
            setting: .temperature,
            at: 0
        )

        XCTAssertEqual(result, [.temperature, .memory])
    }

    func testSlotEditorAddsMetricToSecondSlotWhenFirstSlotIsOccupied() {
        let result = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu],
            setting: .memory,
            at: 1
        )

        XCTAssertEqual(result, [.cpu, .memory])
    }

    func testSlotEditorClearsRequestedSlotOnHidden() {
        let firstSlotCleared = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu, .memory],
            setting: nil,
            at: 0
        )
        XCTAssertEqual(firstSlotCleared, [.memory])

        let secondSlotCleared = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu, .memory],
            setting: nil,
            at: 1
        )
        XCTAssertEqual(secondSlotCleared, [.cpu])
    }

    func testSlotEditorIgnoresHiddenSelectionForUnoccupiedSlot() {
        let result = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu],
            setting: nil,
            at: 1
        )

        XCTAssertEqual(result, [.cpu])
    }

    func testSlotEditorVacatesDuplicateMetricFromOtherSlotOnSameSide() {
        // Selecting `.cpu` for slot 2 while slot 1 already holds `.cpu` must
        // remove the duplicate so the side never lists the same metric twice.
        let result = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu, .memory],
            setting: .cpu,
            at: 1
        )

        XCTAssertEqual(result, [.cpu])
    }

    func testSlotEditorIgnoresOutOfRangeIndex() {
        let result = SystemMonitorSneakSlotEditor.metrics(
            byUpdating: [.cpu],
            setting: .memory,
            at: 5
        )

        XCTAssertEqual(result, [.cpu])
    }

    func testBlockSnapshotCapsTopItemsAtFive() {
        let block = SystemMonitorBlockSnapshot(
            kind: .cpu,
            title: "CPU",
            summary: "22%",
            detail: "load",
            topItems: (1...8).map { index in
                SystemMonitorTopItem(name: "Process \(index)", value: "\(index)%")
            }
        )

        XCTAssertEqual(block.topItems.map(\.name), [
            "Process 1",
            "Process 2",
            "Process 3",
            "Process 4",
            "Process 5",
        ])
    }

    func testCPUBlockKeepsSixRowsToBalanceMemoryCardHeight() {
        let block = SystemMonitorBlockFactory.cpuBlock(
            usage: 0.22,
            topItems: (1...8).map { index in
                SystemMonitorTopItem(name: "Process \(index)", value: "\(index)%")
            }
        )

        XCTAssertEqual(block.topItems.map(\.name), [
            "Process 1",
            "Process 2",
            "Process 3",
            "Process 4",
            "Process 5",
            "Process 6",
        ])
    }

    func testFormattersUseCompactMenuBarValues() {
        XCTAssertEqual(SystemMonitorFormat.percent(0.224), "22%")
        XCTAssertEqual(SystemMonitorFormat.percent(nil), "--")
        XCTAssertEqual(SystemMonitorFormat.temperature(48.2), "48°")
        XCTAssertEqual(SystemMonitorFormat.temperature(nil), "--")
        XCTAssertEqual(SystemMonitorFormat.byteRate(0), "0 KB/s")
        XCTAssertEqual(SystemMonitorFormat.byteRate(2_000), "2 KB/s")
        XCTAssertEqual(SystemMonitorFormat.byteRate(12_400_000), "12.4 MB/s")
        XCTAssertEqual(SystemMonitorFormat.compactByteRate(2_000), "2 KB/s")
        XCTAssertEqual(SystemMonitorFormat.compactByteRate(12_400_000), "12.4MB/s")
        XCTAssertEqual(
            SystemMonitorFormat.directionalRateText(
                downloadBytesPerSecond: 2_000,
                uploadBytesPerSecond: 1_000
            ),
            SystemMonitorDirectionalRateText(upload: "1 KB/s", download: "2 KB/s")
        )
        XCTAssertEqual(
            SystemMonitorFormat.directionalByteRate(downloadBytesPerSecond: 2_000, uploadBytesPerSecond: 1_000),
            "↑1 KB/s ↓2 KB/s"
        )
        XCTAssertEqual(SystemMonitorFormat.diskFree(49_000_000_000), "49.0 GB")
    }

    func testCompactNetworkRowsShowUploadAboveDownload() {
        let snapshot = SystemMonitorSnapshot(
            cpuUsage: nil,
            memoryUsage: nil,
            downloadBytesPerSecond: 95_000,
            uploadBytesPerSecond: 12_000,
            temperatureCelsius: nil,
            diskFreeBytes: nil,
            batteryPercent: nil,
            blocks: SystemMonitorSnapshot.unavailable.blocks
        )

        XCTAssertEqual(snapshot.compactNetworkRows, [
            SystemMonitorSneakNetworkRow(symbolSystemName: "arrow.up.right", value: "12 KB/s"),
            SystemMonitorSneakNetworkRow(symbolSystemName: "arrow.down.left", value: "95 KB/s"),
        ])
    }

    func testUnavailableSnapshotLabelsMemoryPressureAndUsage() {
        let snapshot = SystemMonitorSnapshot.unavailable
        let memoryBlock = snapshot.blocks.first(where: { $0.kind == .memory })

        XCTAssertEqual(memoryBlock?.summary, "--")
        XCTAssertEqual(memoryBlock?.detail, "Pressure -- · Memory --")
    }

    func testUnavailableSnapshotStillHasStableDashboardBlocks() {
        let snapshot = SystemMonitorSnapshot.unavailable

        XCTAssertEqual(snapshot.blocks.map(\.kind), [.cpu, .memory, .network, .disk])
        XCTAssertEqual(snapshot.blocks.first(where: { $0.kind == .network })?.topItems.count, 3)
        XCTAssertEqual(snapshot.blocks.first(where: { $0.kind == .network })?.topItems.map(\.value), [
            "0 KB/s",
            "0 KB/s",
            "0 KB/s",
        ])
        XCTAssertEqual(snapshot.blocks.first(where: { $0.kind == .network })?.topItems.map(\.secondaryValue), [
            "0 KB/s",
            "0 KB/s",
            "0 KB/s",
        ])
        XCTAssertEqual(snapshot.cpuText, "--")
        XCTAssertEqual(snapshot.memoryText, "--")
        XCTAssertEqual(snapshot.downloadText, "--")
        XCTAssertEqual(snapshot.uploadText, "--")
        XCTAssertEqual(snapshot.temperatureText, "--")
    }

    func testNetworkBlockAlwaysHasThreeRowsWithZeroPlaceholders() {
        let block = SystemMonitorBlockFactory.networkBlock(
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 1_000,
            topItems: [
                SystemMonitorTopItem(
                    id: "spotify-network",
                    name: "Spotify",
                    value: "0 KB/s",
                    secondaryValue: "1 KB/s"
                ),
            ]
        )

        XCTAssertEqual(block.summary, "↑1 KB/s ↓0 KB/s")
        XCTAssertEqual(block.topItems.map(\.name), ["Spotify", "—", "—"])
        XCTAssertEqual(block.topItems.map(\.value), [
            "0 KB/s",
            "0 KB/s",
            "0 KB/s",
        ])
        XCTAssertEqual(block.topItems.map(\.secondaryValue), [
            "1 KB/s",
            "0 KB/s",
            "0 KB/s",
        ])
    }

    func testSystemStatusBlockCombinesDiskTemperatureAndBattery() {
        let block = SystemMonitorBlockFactory.diskStatusBlock(
            diskFreeBytes: 48_600_000_000,
            temperatureCelsius: 42.4,
            batteryPercent: 0.67
        )

        XCTAssertEqual(block.title, "SYSTEM")
        XCTAssertEqual(block.summary, "")
        XCTAssertEqual(block.detail, "")
        XCTAssertEqual(block.topItems, [
            SystemMonitorTopItem(id: "system-disk-free", name: "Disk Free", value: "48.6 GB"),
            SystemMonitorTopItem(id: "system-temperature", name: "Temperature", value: "42°"),
            SystemMonitorTopItem(id: "system-battery", name: "Battery", value: "67%"),
        ])
    }

    func testDashboardLayoutInlinesSystemBlockWithNetworkColumn() {
        let layout = SystemMonitorDashboardLayout(snapshot: SystemMonitorSnapshot.unavailable)

        XCTAssertEqual(layout.primaryBlocks.map(\.kind), [.cpu, .memory, .network])
        XCTAssertEqual(layout.inlineSystemBlock?.kind, .disk)
    }

    func testDashboardLayoutAllocatesMoreWidthToNetworkThanCPU() {
        let layout = SystemMonitorDashboardLayout(snapshot: SystemMonitorSnapshot.unavailable)
        let cpuWidth = layout.primaryBlockWidth(for: .cpu, availableWidth: 720, spacing: 8)
        let memoryWidth = layout.primaryBlockWidth(for: .memory, availableWidth: 720, spacing: 8)
        let networkWidth = layout.primaryBlockWidth(for: .network, availableWidth: 720, spacing: 8)

        XCTAssertGreaterThan(networkWidth, cpuWidth)
        XCTAssertGreaterThan(networkWidth, memoryWidth)
        XCTAssertGreaterThan(layout.primaryBlockWidthWeight(for: .network), layout.primaryBlockWidthWeight(for: .cpu))
        XCTAssertGreaterThan(layout.primaryBlockWidthWeight(for: .network), layout.primaryBlockWidthWeight(for: .memory))
    }
}
