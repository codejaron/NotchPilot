import AppKit
import SwiftUI

@MainActor
enum SystemMonitorSneakPreviewLayout {
    static let outerPadding: CGFloat = 10
    static let minimumSideFrameWidth: CGFloat = 34
    static let metricSpacing: CGFloat = 8
    static let labelValueSpacing: CGFloat = 3
    static let networkArrowValueSpacing: CGFloat = 5
    static let reservedNetworkValueSample = "999 KB/s"

    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    private static let networkValueFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
    private static let networkArrowFont = NSFont.systemFont(ofSize: 8, weight: .bold)

    static func sideFrameWidth(
        snapshot: SystemMonitorSnapshot,
        configuration: SystemMonitorSneakConfiguration
    ) -> CGFloat {
        max(
            minimumSideFrameWidth,
            sideWidth(for: configuration.leftMetrics, snapshot: snapshot),
            sideWidth(for: configuration.rightMetrics, snapshot: snapshot)
        )
    }

    static func totalWidth(compactNotchWidth: CGFloat, sideFrameWidth: CGFloat) -> CGFloat {
        (outerPadding * 2) + compactNotchWidth + (sideFrameWidth * 2)
    }

    private static func sideWidth(for metrics: [SystemMonitorMetric], snapshot: SystemMonitorSnapshot) -> CGFloat {
        guard metrics.isEmpty == false else {
            return 0
        }

        let metricsWidth = metrics
            .map { metricWidth(for: $0, snapshot: snapshot) }
            .reduce(0, +)
        return metricsWidth + (CGFloat(metrics.count - 1) * metricSpacing)
    }

    private static func metricWidth(for metric: SystemMonitorMetric, snapshot: SystemMonitorSnapshot) -> CGFloat {
        if metric == .network {
            return networkArrowColumnWidth(snapshot: snapshot)
                + networkArrowValueSpacing
                + networkValueColumnWidth(snapshot: snapshot)
        }

        return textWidth(metric.compactLabel, font: labelFont)
            + labelValueSpacing
            + textWidth(metric.compactValue(in: snapshot), font: valueFont)
    }

    static func networkArrowColumnWidth(snapshot: SystemMonitorSnapshot) -> CGFloat {
        max(
            snapshot.compactNetworkRows.map { textWidth(symbolText(for: $0.symbolSystemName), font: networkArrowFont) }.max() ?? 0,
            textWidth("↗", font: networkArrowFont),
            textWidth("↙", font: networkArrowFont)
        )
    }

    static func networkValueColumnWidth(snapshot: SystemMonitorSnapshot) -> CGFloat {
        max(
            textWidth(reservedNetworkValueSample, font: networkValueFont),
            snapshot.compactNetworkRows.map { textWidth($0.value, font: networkValueFont) }.max() ?? 0
        )
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        guard text.isEmpty == false else {
            return 0
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private static func symbolText(for systemName: String) -> String {
        switch systemName {
        case "arrow.up.right":
            return "↗"
        case "arrow.down.left":
            return "↙"
        default:
            return ""
        }
    }
}

struct SystemMonitorSneakPreviewView: View {
    let snapshot: SystemMonitorSnapshot
    let configuration: SystemMonitorSneakConfiguration
    let context: NotchContext
    let sideFrameWidth: CGFloat
    let totalWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: SystemMonitorSneakPreviewLayout.metricSpacing) {
                ForEach(configuration.leftMetrics, id: \.self) { metric in
                    compactMetric(metric)
                }
            }
            .frame(width: sideFrameWidth, alignment: .leading)

            Spacer(minLength: context.notchGeometry.compactSize.width)

            HStack(spacing: SystemMonitorSneakPreviewLayout.metricSpacing) {
                ForEach(configuration.rightMetrics, id: \.self) { metric in
                    compactMetric(metric)
                }
            }
            .frame(width: sideFrameWidth, alignment: .trailing)
        }
        .padding(.horizontal, SystemMonitorSneakPreviewLayout.outerPadding)
        .frame(width: totalWidth, height: context.notchGeometry.compactSize.height, alignment: .center)
    }

    @ViewBuilder
    private func compactMetric(_ metric: SystemMonitorMetric) -> some View {
        if metric == .network {
            networkMetric
        } else {
            textMetric(metric)
        }
    }

    private func textMetric(_ metric: SystemMonitorMetric) -> some View {
        HStack(spacing: 4) {
            Text(metric.compactLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)

            Text(metric.compactValue(in: snapshot))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .minimumScaleFactor(0.75)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var networkMetric: some View {
        let arrowWidth = SystemMonitorSneakPreviewLayout.networkArrowColumnWidth(snapshot: snapshot)
        let valueWidth = SystemMonitorSneakPreviewLayout.networkValueColumnWidth(snapshot: snapshot)

        return HStack(spacing: SystemMonitorSneakPreviewLayout.networkArrowValueSpacing) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(snapshot.compactNetworkRows.enumerated()), id: \.offset) { rowEntry in
                    let row = rowEntry.element
                    HStack(spacing: SystemMonitorSneakPreviewLayout.networkArrowValueSpacing) {
                        Image(systemName: row.symbolSystemName)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                            .frame(width: arrowWidth, alignment: .trailing)

                        Text(row.value)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                            .monospacedDigit()
                            .frame(width: valueWidth, alignment: .trailing)
                    }
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private extension SystemMonitorMetric {
    var compactLabel: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "MEM"
        case .network:
            return "NET"
        case .temperature:
            return "TMP"
        case .disk:
            return "DSK"
        case .battery:
            return "BAT"
        }
    }

    func compactValue(in snapshot: SystemMonitorSnapshot) -> String {
        switch self {
        case .cpu:
            return snapshot.cpuText
        case .memory:
            return snapshot.memoryText
        case .network:
            return snapshot.downloadText
        case .temperature:
            return snapshot.temperatureText
        case .disk:
            return SystemMonitorFormat.diskFree(snapshot.diskFreeBytes)
        case .battery:
            return snapshot.batteryText
        }
    }
}

struct SystemMonitorDashboardView: View {
    let snapshot: SystemMonitorSnapshot
    let accentColor: Color

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(snapshot.blocks) { block in
                        SystemMonitorBlockView(block: block, accentColor: accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum SystemMonitorDashboardTypography {
    static let rowNameFontSize: CGFloat = 11
    static let standardRowValueFontSize: CGFloat = 12
    static let networkRowValueFontSize: CGFloat = 12
    static let systemStatusRowValueFontSize: CGFloat = 12
    static let systemStatusUsesMonospacedRowValues = false
    static let standardSummaryFontSize: CGFloat = 18
    static let networkSummaryFontSize: CGFloat = 13
    static let detailFontSize: CGFloat = 10
}

private struct SystemMonitorBlockView: View {
    let block: SystemMonitorBlockSnapshot
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(block.title)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(accentColor)

                Spacer(minLength: 0)

                Text(block.summary)
                    .font(.system(size: summaryFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            if block.detail.isEmpty == false {
                Text(block.detail)
                    .font(.system(size: SystemMonitorDashboardTypography.detailFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(block.topItems) { item in
                    HStack(spacing: 5) {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        Text(item.value)
                            .font(.system(size: rowValueFontSize, weight: rowValueWeight, design: rowValueDesign))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .layoutPriority(1)
                    }
                    .font(
                        .system(
                            size: SystemMonitorDashboardTypography.rowNameFontSize,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(minHeight: 88, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
    }

    private var summaryFontSize: CGFloat {
        block.kind == .network
            ? SystemMonitorDashboardTypography.networkSummaryFontSize
            : SystemMonitorDashboardTypography.standardSummaryFontSize
    }

    private var rowValueFontSize: CGFloat {
        switch block.kind {
        case .network:
            return SystemMonitorDashboardTypography.networkRowValueFontSize
        case .disk:
            return SystemMonitorDashboardTypography.systemStatusRowValueFontSize
        default:
            return SystemMonitorDashboardTypography.standardRowValueFontSize
        }
    }

    private var rowValueWeight: Font.Weight {
        block.kind == .disk ? .semibold : .bold
    }

    private var rowValueDesign: Font.Design {
        block.kind == .disk ? .rounded : .monospaced
    }
}
