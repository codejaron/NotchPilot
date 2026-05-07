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
        configuration: SystemMonitorSneakConfiguration,
        language: AppLanguage
    ) -> CGFloat {
        max(
            minimumSideFrameWidth,
            sideWidth(for: configuration.leftMetrics, snapshot: snapshot, language: language),
            sideWidth(for: configuration.rightMetrics, snapshot: snapshot, language: language)
        )
    }

    static func totalWidth(compactNotchWidth: CGFloat, sideFrameWidth: CGFloat) -> CGFloat {
        (outerPadding * 2) + compactNotchWidth + (sideFrameWidth * 2)
    }

    private static func sideWidth(
        for metrics: [SystemMonitorMetric],
        snapshot: SystemMonitorSnapshot,
        language: AppLanguage
    ) -> CGFloat {
        guard metrics.isEmpty == false else {
            return 0
        }

        let metricsWidth = metrics
            .map { metricWidth(for: $0, snapshot: snapshot, language: language) }
            .reduce(0, +)
        return metricsWidth + (CGFloat(metrics.count - 1) * metricSpacing)
    }

    private static func metricWidth(
        for metric: SystemMonitorMetric,
        snapshot: SystemMonitorSnapshot,
        language: AppLanguage
    ) -> CGFloat {
        if metric == .network {
            return networkArrowColumnWidth(snapshot: snapshot)
                + networkArrowValueSpacing
                + networkValueColumnWidth(snapshot: snapshot)
        }

        return textWidth(metric.compactLabel(language: language), font: labelFont)
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
    @ObservedObject private var store = SettingsStore.shared

    let snapshot: SystemMonitorSnapshot
    let configuration: SystemMonitorSneakConfiguration
    let activeAlerts: [SystemMonitorMetric: SystemMonitorActiveAlert]
    let context: NotchContext
    let sideFrameWidth: CGFloat
    let totalWidth: CGFloat

    init(
        snapshot: SystemMonitorSnapshot,
        configuration: SystemMonitorSneakConfiguration,
        activeAlerts: [SystemMonitorMetric: SystemMonitorActiveAlert] = [:],
        context: NotchContext,
        sideFrameWidth: CGFloat,
        totalWidth: CGFloat
    ) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.activeAlerts = activeAlerts
        self.context = context
        self.sideFrameWidth = sideFrameWidth
        self.totalWidth = totalWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: SystemMonitorSneakPreviewLayout.metricSpacing) {
                ForEach(configuration.leftMetrics, id: \.self) { metric in
                    compactMetric(metric)
                        .transition(SystemMonitorSneakPreviewAnimation.metricTransition)
                }
            }
            .animation(SystemMonitorSneakPreviewAnimation.layoutSpring, value: configuration.leftMetrics)
            .frame(width: sideFrameWidth, alignment: .leading)

            Spacer(minLength: context.notchGeometry.compactSize.width)

            HStack(spacing: SystemMonitorSneakPreviewLayout.metricSpacing) {
                ForEach(configuration.rightMetrics, id: \.self) { metric in
                    compactMetric(metric)
                        .transition(SystemMonitorSneakPreviewAnimation.metricTransition)
                }
            }
            .animation(SystemMonitorSneakPreviewAnimation.layoutSpring, value: configuration.rightMetrics)
            .frame(width: sideFrameWidth, alignment: .trailing)
        }
        .padding(.horizontal, SystemMonitorSneakPreviewLayout.outerPadding)
        .frame(width: totalWidth, height: context.notchGeometry.compactSize.height, alignment: .center)
        .animation(SystemMonitorSneakPreviewAnimation.layoutSpring, value: totalWidth)
    }

    @ViewBuilder
    private func compactMetric(_ metric: SystemMonitorMetric) -> some View {
        SystemMonitorCompactMetricView(
            metric: metric,
            snapshot: snapshot,
            alert: activeAlerts[metric],
            language: store.interfaceLanguage
        )
    }
}

/// Coordinates the animation grammar for the sneak preview. Centralised so that
/// every metric uses the same spring/curve set and tweaks stay in one place.
@MainActor
enum SystemMonitorSneakPreviewAnimation {
    static let layoutSpring: Animation = .spring(response: 0.55, dampingFraction: 0.78)
    static let pulseDuration: Double = 0.42
    static let breathingDuration: Double = 1.6
    static let pulseScalePeak: CGFloat = 1.12
    static let breathingScaleAmplitude: CGFloat = 0.04
    static let haloDuration: Double = 0.6

    static let metricTransition: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.6, anchor: .center).combined(with: .opacity),
        removal: .scale(scale: 0.85, anchor: .center).combined(with: .opacity)
    )
}

private struct SystemMonitorCompactMetricView: View {
    let metric: SystemMonitorMetric
    let snapshot: SystemMonitorSnapshot
    let alert: SystemMonitorActiveAlert?
    let language: AppLanguage

    @State private var pulseTrigger = false
    @State private var breathingPhase: CGFloat = 0
    @State private var lastFiredID: String?

    var body: some View {
        Group {
            if metric == .network {
                networkMetric
            } else {
                textMetric
            }
        }
        .scaleEffect(currentScale)
        .background(haloBackground)
        .onAppear { syncFireState(initial: true) }
        .onChange(of: alert?.triggeringRuleID) { _, _ in
            syncFireState(initial: false)
        }
        .onChange(of: alert?.severity) { _, _ in
            syncFireState(initial: false)
        }
    }

    // MARK: - Subviews

    private var textMetric: some View {
        HStack(spacing: 4) {
            Text(metric.compactLabel(language: language))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)

            Text(metric.compactValue(in: snapshot))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.75)
                .shadow(
                    color: criticalGlowColor,
                    radius: criticalGlowRadius
                )
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
                            .foregroundStyle(valueColor)
                            .monospacedDigit()
                            .frame(width: valueWidth, alignment: .trailing)
                    }
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .shadow(
            color: criticalGlowColor,
            radius: criticalGlowRadius
        )
    }

    @ViewBuilder
    private var haloBackground: some View {
        if pulseTrigger, let alert {
            Circle()
                .fill(SystemMonitorAlertVisuals.color(for: alert.severity).opacity(0.55))
                .blur(radius: 12)
                .scaleEffect(pulseTrigger ? 1.45 : 0.5)
                .opacity(pulseTrigger ? 0.0 : 0.7)
                .animation(
                    .easeOut(duration: SystemMonitorSneakPreviewAnimation.haloDuration),
                    value: pulseTrigger
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: - Severity-driven styling

    private var valueColor: Color {
        guard let alert else {
            return NotchPilotTheme.islandTextPrimary
        }
        return SystemMonitorAlertVisuals.color(for: alert.severity)
    }

    private var criticalGlowColor: Color {
        guard let alert, alert.severity == .critical else {
            return .clear
        }
        return SystemMonitorAlertVisuals.color(for: .critical).opacity(0.45)
    }

    private var criticalGlowRadius: CGFloat {
        guard let alert, alert.severity == .critical else {
            return 0
        }
        // Subtle breathing-driven radius so the critical glow feels alive
        // without becoming distracting.
        return 5 + breathingPhase * 4
    }

    private var currentScale: CGFloat {
        let pulse = pulseTrigger ? SystemMonitorSneakPreviewAnimation.pulseScalePeak : 1.0
        let breathing: CGFloat
        if alert?.severity == .critical {
            breathing = 1 + breathingPhase * SystemMonitorSneakPreviewAnimation.breathingScaleAmplitude
        } else {
            breathing = 1
        }
        return pulse * breathing
    }

    // MARK: - State coordination

    private func syncFireState(initial: Bool) {
        let currentID = alert?.triggeringRuleID
        let isNewFire = currentID != nil && currentID != lastFiredID
        lastFiredID = currentID

        if alert?.severity == .critical {
            startBreathingIfNeeded()
        } else {
            stopBreathing()
        }

        if isNewFire && initial == false {
            triggerPulse()
        }
    }

    private func triggerPulse() {
        // 1.0 → 1.12 spring up, then settle back to 1.0. Using a one-shot
        // boolean so SwiftUI can drive the spring on both legs.
        pulseTrigger = true
        DispatchQueue.main.asyncAfter(deadline: .now() + SystemMonitorSneakPreviewAnimation.pulseDuration) {
            withAnimation(SystemMonitorSneakPreviewAnimation.layoutSpring) {
                pulseTrigger = false
            }
        }
    }

    private func startBreathingIfNeeded() {
        guard breathingPhase == 0 else { return }
        withAnimation(
            .easeInOut(duration: SystemMonitorSneakPreviewAnimation.breathingDuration)
                .repeatForever(autoreverses: true)
        ) {
            breathingPhase = 1
        }
    }

    private func stopBreathing() {
        guard breathingPhase != 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            breathingPhase = 0
        }
    }
}

/// Maps alert severities to the sneak preview's visual language. Kept as a
/// flat enum so other UI surfaces (dashboard, future banners) can share the
/// same palette without re-implementing the mapping.
enum SystemMonitorAlertVisuals {
    static func color(for severity: SystemMonitorAlertSeverity) -> Color {
        switch severity {
        case .info:
            return Color(red: 0.40, green: 0.85, blue: 0.95)    // cyan/teal
        case .warn:
            return Color(red: 1.00, green: 0.74, blue: 0.27)    // amber
        case .critical:
            return Color(red: 1.00, green: 0.40, blue: 0.36)    // red
        }
    }
}

private extension SystemMonitorMetric {
    func compactLabel(language: AppLanguage) -> String {
        AppStrings.systemMonitorCompactMetricTitle(self, language: language)
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

    var body: some View {
        let layout = SystemMonitorDashboardLayout(snapshot: snapshot)

        return GeometryReader { geometry in
            HStack(alignment: .top, spacing: 8) {
                ForEach(layout.primaryBlocks) { block in
                    SystemMonitorBlockView(
                        block: block,
                        accentColor: accentColor,
                        networkSummary: block.kind == .network ? snapshot.directionalRateText : nil,
                        supplementaryBlock: block.kind == .network ? layout.inlineSystemBlock : nil
                    )
                    .frame(
                        width: layout.primaryBlockWidth(
                            for: block.kind,
                            availableWidth: geometry.size.width,
                            spacing: 8
                        ),
                        alignment: .topLeading
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SystemMonitorDashboardLayout: Equatable {
    private static let primaryBlockWidthWeights: [SystemMonitorMetric: CGFloat] = [
        .cpu: 0.86,
        .memory: 0.94,
        .network: 1.20,
    ]

    let primaryBlocks: [SystemMonitorBlockSnapshot]
    let inlineSystemBlock: SystemMonitorBlockSnapshot?

    init(snapshot: SystemMonitorSnapshot) {
        let cpuBlock = snapshot.blocks.first { $0.kind == .cpu }
        let memoryBlock = snapshot.blocks.first { $0.kind == .memory }
        let networkBlock = snapshot.blocks.first { $0.kind == .network }

        self.primaryBlocks = [cpuBlock, memoryBlock, networkBlock].compactMap { $0 }
        self.inlineSystemBlock = snapshot.blocks.first { $0.kind == .disk }
    }

    func primaryBlockWidth(
        for metric: SystemMonitorMetric,
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard primaryBlocks.isEmpty == false else {
            return 0
        }

        let totalSpacing = CGFloat(max(primaryBlocks.count - 1, 0)) * spacing
        let usableWidth = max(0, availableWidth - totalSpacing)
        let totalWeight = primaryBlocks.reduce(CGFloat(0)) { partialResult, block in
            partialResult + primaryBlockWidthWeight(for: block.kind)
        }
        guard totalWeight > 0 else {
            return usableWidth / CGFloat(primaryBlocks.count)
        }

        return usableWidth * primaryBlockWidthWeight(for: metric) / totalWeight
    }

    func primaryBlockWidthWeight(for metric: SystemMonitorMetric) -> CGFloat {
        Self.primaryBlockWidthWeights[metric] ?? 1
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
    @ObservedObject private var store = SettingsStore.shared

    let block: SystemMonitorBlockSnapshot
    let accentColor: Color
    var networkSummary: SystemMonitorDirectionalRateText? = nil
    var supplementaryBlock: SystemMonitorBlockSnapshot? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: supplementaryBlock == nil ? 0 : 9) {
            Group {
                if block.kind == .disk {
                    systemStatusBody
                } else if block.kind == .network {
                    networkBody
                } else {
                    standardBody
                }
            }

            if let supplementaryBlock {
                inlineSystemBody(supplementaryBlock)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(minHeight: blockMinHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
    }

    private var networkBody: some View {
        let summary = networkSummary ?? SystemMonitorDirectionalRateText(upload: "--", download: "--")
        let valueLayout = SystemMonitorNetworkValueLayout(
            summary: summary,
            topItems: block.topItems
        )

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(AppStrings.systemMonitorBlockTitle(block.kind, language: store.interfaceLanguage))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    networkMetricValue(
                        symbolSystemName: "arrow.up.right",
                        value: summary.upload,
                        fontSize: SystemMonitorDashboardTypography.networkSummaryFontSize,
                        width: valueLayout.summaryUploadWidth
                    )
                    networkMetricValue(
                        symbolSystemName: "arrow.down.left",
                        value: summary.download,
                        fontSize: SystemMonitorDashboardTypography.networkSummaryFontSize,
                        width: valueLayout.summaryDownloadWidth
                    )
                }
                .layoutPriority(1)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(block.topItems) { item in
                    HStack(spacing: 5) {
                        Text(AppStrings.systemMonitorTopItemName(item.name, language: store.interfaceLanguage))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        HStack(spacing: 6) {
                            networkMetricValue(
                                symbolSystemName: "arrow.up.right",
                                value: item.value,
                                fontSize: SystemMonitorDashboardTypography.networkRowValueFontSize,
                                width: valueLayout.uploadWidth
                            )
                            networkMetricValue(
                                symbolSystemName: "arrow.down.left",
                                value: item.secondaryValue ?? "--",
                                fontSize: SystemMonitorDashboardTypography.networkRowValueFontSize,
                                width: valueLayout.downloadWidth
                            )
                        }
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
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(AppStrings.systemMonitorBlockTitle(block.kind, language: store.interfaceLanguage))
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
                Text(AppStrings.systemMonitorDetail(block.detail, language: store.interfaceLanguage))
                    .font(.system(size: SystemMonitorDashboardTypography.detailFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(block.topItems) { item in
                    HStack(spacing: 5) {
                        Text(AppStrings.systemMonitorTopItemName(item.name, language: store.interfaceLanguage))
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
    }

    private func networkMetricValue(
        symbolSystemName: String,
        value: String,
        fontSize: CGFloat,
        width: CGFloat?
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbolSystemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                .frame(width: SystemMonitorNetworkValueLayout.arrowWidth, alignment: .center)

            Text(value)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .frame(width: width, alignment: .trailing)
    }

    private var systemStatusBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.systemMonitorBlockTitle(block.kind, language: store.interfaceLanguage))
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(accentColor)

            HStack(alignment: .top, spacing: 14) {
                ForEach(block.topItems) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.systemMonitorTopItemName(item.name, language: store.interfaceLanguage))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.9))
                            .lineLimit(1)

                        Text(item.value)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func inlineSystemBody(_ systemBlock: SystemMonitorBlockSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AppStrings.systemMonitorBlockTitle(systemBlock.kind, language: store.interfaceLanguage))
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(accentColor)

            HStack(alignment: .top, spacing: 10) {
                ForEach(systemBlock.topItems) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.systemMonitorTopItemName(item.name, language: store.interfaceLanguage))
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.88))
                            .lineLimit(1)

                        Text(item.value)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    private var blockMinHeight: CGFloat {
        block.kind == .disk ? 72 : 88
    }
}

private struct SystemMonitorNetworkValueLayout {
    static let arrowWidth: CGFloat = 10
    private static let reservedRateSample = "99.9 MB/s"
    private static let metricSpacing: CGFloat = 3

    let summaryUploadWidth: CGFloat
    let summaryDownloadWidth: CGFloat
    let uploadWidth: CGFloat
    let downloadWidth: CGFloat

    init(summary: SystemMonitorDirectionalRateText, topItems: [SystemMonitorTopItem]) {
        let summaryFont = NSFont.monospacedSystemFont(
            ofSize: SystemMonitorDashboardTypography.networkSummaryFontSize,
            weight: .bold
        )
        let rowFont = NSFont.monospacedSystemFont(
            ofSize: SystemMonitorDashboardTypography.networkRowValueFontSize,
            weight: .bold
        )
        self.summaryUploadWidth = Self.metricWidth(
            for: [summary.upload],
            font: summaryFont
        )
        self.summaryDownloadWidth = Self.metricWidth(
            for: [summary.download],
            font: summaryFont
        )
        self.uploadWidth = Self.metricWidth(for: topItems.map(\.value), font: rowFont)
        self.downloadWidth = Self.metricWidth(
            for: topItems.map { $0.secondaryValue ?? "--" },
            font: rowFont
        )
    }

    private static func metricWidth(for values: [String], font: NSFont) -> CGFloat {
        let largestValueWidth = max(
            textWidth(reservedRateSample, font: font),
            values.map { textWidth($0, font: font) }.max() ?? 0
        )
        return arrowWidth + metricSpacing + largestValueWidth
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        guard text.isEmpty == false else {
            return 0
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}
