import AppKit
import SwiftUI

// MARK: - Compact preview layout

struct NotificationsCompactPreviewLine: Equatable, Hashable {
    let title: String?
    let body: String?

    var hasTitle: Bool {
        title?.isEmpty == false
    }

    var hasBody: Bool {
        body?.isEmpty == false
    }
}

enum NotificationsCompactPreviewLayout {
    static let outerPadding: CGFloat = 10
    static let iconTileSize: CGFloat = 28
    static let leftFrameBaseWidth: CGFloat = 36
    static let rightFrameMinWidth: CGFloat = 68
    static let rightFrameMaxWidth: CGFloat = 220
    static let rightFrameTextMargin: CGFloat = 16
    static let foldedCountBadgeWidth: CGFloat = 34
    static let contentRowHorizontalPadding: CGFloat = 8
    static let contentRowVerticalPadding: CGFloat = 8
    static let appNameFontSize: CGFloat = 12
    static let titleFontSize: CGFloat = 12
    static let bodyFontSize: CGFloat = 10.5
    static let titleLineHeight: CGFloat = 15
    static let bodyLineHeight: CGFloat = 14
    static let messageGroupSpacing: CGFloat = 3

    static func leftFrameWidth() -> CGFloat {
        leftFrameBaseWidth
    }

    /// Measure the rendered width of the app name with our chosen font, clamped to [min, max].
    ///
    /// SwiftUI's `.font(.system(size:weight:design: .rounded))` renders with SF Pro Rounded,
    /// which is slightly wider than the default SF Pro Text. We mirror that here so the measured
    /// width matches the on-screen rendering (otherwise the right edge truncates names).
    static func rightFrameWidth(forAppName name: String, foldedCount: Int = 0) -> CGFloat {
        let baseFont = NSFont.systemFont(ofSize: appNameFontSize, weight: .semibold)
        let renderFont: NSFont
        if let descriptor = baseFont.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: appNameFontSize) {
            renderFont = rounded
        } else {
            renderFont = baseFont
        }
        let measured = (name as NSString).size(withAttributes: [.font: renderFont]).width
        let badgeWidth = foldedCount > 0 ? foldedCountBadgeWidth + 6 : 0
        let raw = ceil(measured) + rightFrameTextMargin + badgeWidth
        return min(max(raw, rightFrameMinWidth), rightFrameMaxWidth)
    }

    static func extensionHeight(for lines: [NotificationsCompactPreviewLine]) -> CGFloat {
        guard lines.isEmpty == false else { return 0 }

        let contentHeight = lines.reduce(CGFloat(0)) { height, line in
            var lineHeight: CGFloat = contentRowVerticalPadding * 2
            if line.hasTitle {
                lineHeight += titleLineHeight
            }
            if line.hasBody {
                lineHeight += bodyLineHeight
                if line.hasTitle {
                    lineHeight += 1
                }
            }
            return height + lineHeight
        }
        let spacing = CGFloat(max(0, lines.count - 1)) * messageGroupSpacing
        return contentHeight + spacing
    }

    static func totalWidth(compactWidth: CGFloat, leftFrameWidth: CGFloat, rightFrameWidth: CGFloat) -> CGFloat {
        compactWidth + leftFrameWidth + rightFrameWidth + outerPadding * 2
    }
}

// MARK: - Compact preview view

struct NotificationsCompactPreview: View {
    let bundleIdentifier: String
    let appDisplayName: String
    let contentLines: [NotificationsCompactPreviewLine]
    let foldedCount: Int
    let cameraClearanceWidth: CGFloat
    let notchHeight: CGFloat
    let leftFrameWidth: CGFloat
    let rightFrameWidth: CGFloat
    let totalWidth: CGFloat
    let extensionHeight: CGFloat
    let accentColor: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                brandCluster
                    .frame(width: leftFrameWidth, alignment: .leading)

                Spacer(minLength: 0)
                    .frame(width: cameraClearanceWidth)

                appNameCluster
                    .frame(width: rightFrameWidth, alignment: .trailing)
            }
            .frame(height: notchHeight, alignment: .center)

            if extensionHeight > 0 {
                contentRow
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: extensionHeight, alignment: .top)
            }
        }
        .padding(.horizontal, NotificationsCompactPreviewLayout.outerPadding)
        .frame(
            width: totalWidth,
            height: notchHeight + extensionHeight,
            alignment: .top
        )
    }

    private var brandCluster: some View {
        HStack(spacing: 0) {
            NotificationAppIconView(
                bundleIdentifier: bundleIdentifier,
                accentColor: accentColor,
                size: NotificationsCompactPreviewLayout.iconTileSize
            )
        }
    }

    private var appNameCluster: some View {
        HStack(spacing: 6) {
            Text(appDisplayName)
                .font(.system(size: NotificationsCompactPreviewLayout.appNameFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            if foldedCount > 0 {
                Text("+\(foldedCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(0.16))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(accentColor.opacity(0.24), lineWidth: 1)
                    }
            }
        }
    }

    @ViewBuilder
    private var contentRow: some View {
        ZStack(alignment: .topLeading) {
            if foldedCount > 0 {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    }
                    .offset(x: 12, y: 5)

                if foldedCount > 1 {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                        }
                        .offset(x: 24, y: 9)
                }
            }

            VStack(alignment: .leading, spacing: NotificationsCompactPreviewLayout.messageGroupSpacing) {
                ForEach(Array(contentLines.enumerated()), id: \.offset) { index, line in
                    lineCard(line, isLatest: index == 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NotificationsCompactPreviewLayout.contentRowHorizontalPadding)
    }

    private func lineCard(_ line: NotificationsCompactPreviewLine, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: NotificationsCompactPreviewLayout.messageGroupSpacing) {
            if let title = line.title, title.isEmpty == false {
                Text(title)
                    .font(.system(size: NotificationsCompactPreviewLayout.titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(1)
            }
            if let body = line.body, body.isEmpty == false {
                Text(body)
                    .font(.system(size: NotificationsCompactPreviewLayout.bodyFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, NotificationsCompactPreviewLayout.contentRowVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(isLatest ? 0.06 : 0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(isLatest ? 0.08 : 0.06), lineWidth: 1)
        }
    }
}

// MARK: - Expanded dashboard view

struct NotificationsDashboardView: View {
    @ObservedObject var store: NotificationHistoryStore
    @ObservedObject var settings = SettingsStore.shared
    let runtimeState: NotificationsPluginRuntimeState
    let diagnostics: NotificationsRuntimeDiagnostics
    let accentColor: Color
    let onLaunch: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            diagnosticStrip
            switch runtimeState {
            case .awaitingFullDiskAccess:
                permissionsCard(title: AppStrings.text(.notificationsPermissionsMissing, language: settings.interfaceLanguage))
            case .databaseNotFound:
                permissionsCard(title: AppStrings.text(.notificationsDatabaseNotFound, language: settings.interfaceLanguage))
            case .databaseUnreadable(let msg):
                permissionsCard(title: msg)
            case .disabled, .running:
                listContent
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    private var diagnosticStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
            Text(stateText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var stateColor: Color {
        switch runtimeState {
        case .disabled:                return Color.gray
        case .awaitingFullDiskAccess:  return Color.orange
        case .databaseNotFound:        return Color.red
        case .databaseUnreadable:      return Color.red
        case .running:                 return Color.green
        }
    }

    private var stateText: String {
        let language = settings.interfaceLanguage
        switch runtimeState {
        case .disabled:
            return AppStrings.text(.notificationsStateDisabled, language: language)
        case .awaitingFullDiskAccess:
            return AppStrings.text(.notificationsStateNoFDA, language: language)
        case .databaseNotFound:
            return AppStrings.text(.notificationsStateDBNotFound, language: language)
        case .databaseUnreadable:
            return AppStrings.text(.notificationsStateDBUnreadable, language: language)
        case .running:
            let unreadLabel = AppStrings.text(.notificationsUnreadLabel, language: language)
            let count = store.entries.count
            return count > 0
                ? "\(AppStrings.text(.notificationsStateRunning, language: language)) · \(unreadLabel) \(count)"
                : AppStrings.text(.notificationsStateRunning, language: language)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                NotchPilotIconTile(
                    systemName: "bell.badge.fill",
                    accent: accentColor,
                    size: 24,
                    isActive: true
                )
                Text(AppStrings.text(.notifications, language: settings.interfaceLanguage))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            }
            Spacer()
            Button {
                store.clear()
            } label: {
                Label(AppStrings.text(.notificationsMarkAllRead, language: settings.interfaceLanguage), systemImage: "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(store.entries.isEmpty ? 0 : 0.065))
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
            .opacity(store.entries.isEmpty ? 0.3 : 1)
            .disabled(store.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var listContent: some View {
        Group {
            if store.groupedByApp.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.groupedByApp, id: \.bundleID) { group in
                            section(for: group)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NotchPilotTheme.islandTextMuted)
            Text(stateText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    @ViewBuilder
    private func section(for group: (bundleID: String, entries: [NotificationHistoryStore.HistoryEntry])) -> some View {
        let isMuted = group.entries.allSatisfy(\.muted)
        let appName = group.entries.first?.notification.appDisplayName ?? group.bundleID

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                NotificationAppIconView(
                    bundleIdentifier: group.bundleID,
                    accentColor: accentColor,
                    size: 22
                )

                Text(appName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(1)

                Text("\(group.entries.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }

                if isMuted {
                    Text("· \(AppStrings.text(.notificationsRecordedWhileMuted, language: settings.interfaceLanguage))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)

            VStack(spacing: 6) {
                ForEach(group.entries) { entry in
                    row(entry: entry)
                }
            }
        }
    }

    private func row(entry: NotificationHistoryStore.HistoryEntry) -> some View {
        let titleText = entry.notification.title ?? entry.notification.subtitle
        let bodyText = entry.notification.body
        let hasAnyContent = (titleText?.isEmpty == false) || (bodyText?.isEmpty == false)
        let fallbackTitle = AppStrings.text(.notificationsNewMessageRedactedTitle, language: settings.interfaceLanguage)

        return Button {
            if settings.notificationsOpenOnClick {
                onLaunch(entry.notification.bundleIdentifier)
            }
            store.remove(id: entry.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(accentColor.opacity(entry.muted ? 0.22 : 0.7))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    if hasAnyContent {
                        if let title = titleText, title.isEmpty == false {
                            Text(title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                                .lineLimit(1)
                        }
                        if let body = bodyText, body.isEmpty == false {
                            Text(body)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text(fallbackTitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextPrimary.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.notification.deliveredAt, style: .time)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.7))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(entry.muted ? 0.03 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(entry.muted ? 0.04 : 0.07), lineWidth: 1)
            )
            .opacity(entry.muted ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.muted {
                Button("\(AppStrings.text(.notificationsAllowedApps, language: settings.interfaceLanguage)) · \(entry.notification.appDisplayName ?? entry.notification.bundleIdentifier)") {
                    let normalizedBundleID = entry.notification.bundleIdentifier.lowercased()
                    var current = Set(settings.notificationsWhitelistedBundleIDs.filter {
                        $0.lowercased() != normalizedBundleID
                    })
                    current.insert(normalizedBundleID)
                    settings.notificationsWhitelistedBundleIDs = current
                }
            }
        }
    }

    private func permissionsCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(AppStrings.text(.notificationsPermissionsTitle, language: settings.interfaceLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
            Button(AppStrings.text(.notificationsOpenSystemSettings, language: settings.interfaceLanguage)) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
        .padding(.horizontal, 12)
    }
}
