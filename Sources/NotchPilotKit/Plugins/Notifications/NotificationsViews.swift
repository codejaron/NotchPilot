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
    static let iconTileSize: CGFloat = 26
    static let leftFrameBaseWidth: CGFloat = 32       // tile only
    static let rightFrameMinWidth: CGFloat = 40
    static let rightFrameMaxWidth: CGFloat = 180
    static let rightFrameTextMargin: CGFloat = 12
    static let contentRowHorizontalPadding: CGFloat = 8
    static let contentRowVerticalPadding: CGFloat = 6
    static let appNameFontSize: CGFloat = 12
    static let titleFontSize: CGFloat = 11
    static let bodyFontSize: CGFloat = 10
    static let titleLineHeight: CGFloat = 14
    static let bodyLineHeight: CGFloat = 13
    static let messageGroupSpacing: CGFloat = 4

    static func leftFrameWidth() -> CGFloat {
        leftFrameBaseWidth
    }

    /// Measure the rendered width of the app name with our chosen font, clamped to [min, max].
    ///
    /// SwiftUI's `.font(.system(size:weight:design: .rounded))` renders with SF Pro Rounded,
    /// which is slightly wider than the default SF Pro Text. We mirror that here so the measured
    /// width matches the on-screen rendering (otherwise the right edge truncates names).
    static func rightFrameWidth(forAppName name: String) -> CGFloat {
        let baseFont = NSFont.systemFont(ofSize: appNameFontSize, weight: .semibold)
        let renderFont: NSFont
        if let descriptor = baseFont.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: appNameFontSize) {
            renderFont = rounded
        } else {
            renderFont = baseFont
        }
        let measured = (name as NSString).size(withAttributes: [.font: renderFont]).width
        let raw = ceil(measured) + rightFrameTextMargin
        return min(max(raw, rightFrameMinWidth), rightFrameMaxWidth)
    }

    static func extensionHeight(for lines: [NotificationsCompactPreviewLine]) -> CGFloat {
        guard lines.isEmpty == false else { return 0 }

        let contentHeight = lines.reduce(CGFloat(0)) { height, line in
            var lineHeight: CGFloat = 0
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
        return contentRowVerticalPadding * 2 + contentHeight + spacing
    }

    static func totalWidth(compactWidth: CGFloat, leftFrameWidth: CGFloat, rightFrameWidth: CGFloat) -> CGFloat {
        compactWidth + leftFrameWidth + rightFrameWidth + outerPadding * 2
    }
}

// MARK: - Compact preview view

struct NotificationsCompactPreview: View {
    let appDisplayName: String
    let contentLines: [NotificationsCompactPreviewLine]
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
        HStack(spacing: 5) {
            NotchPilotIconTile(
                systemName: "bell.badge.fill",
                accent: accentColor,
                size: NotificationsCompactPreviewLayout.iconTileSize,
                isActive: true
            )
        }
    }

    private var appNameCluster: some View {
        Text(appDisplayName)
            .font(.system(size: NotificationsCompactPreviewLayout.appNameFontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var contentRow: some View {
        VStack(alignment: .leading, spacing: NotificationsCompactPreviewLayout.messageGroupSpacing) {
            ForEach(Array(contentLines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 1) {
                    if let title = line.title, title.isEmpty == false {
                        Text(title)
                            .font(.system(size: NotificationsCompactPreviewLayout.titleFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                            .lineLimit(1)
                    }
                    if let body = line.body, body.isEmpty == false {
                        Text(body)
                            .font(.system(size: NotificationsCompactPreviewLayout.bodyFontSize, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NotificationsCompactPreviewLayout.contentRowHorizontalPadding)
        .padding(.vertical, NotificationsCompactPreviewLayout.contentRowVerticalPadding)
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
            Divider().opacity(0.2)
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
        .padding(.horizontal, 4)
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
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
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
            Text(AppStrings.text(.notifications, language: settings.interfaceLanguage))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            Spacer()
            Button {
                store.clear()
            } label: {
                Label(AppStrings.text(.notificationsMarkAllRead, language: settings.interfaceLanguage), systemImage: "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(store.groupedByApp, id: \.bundleID) { group in
                    section(for: group)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func section(for group: (bundleID: String, entries: [NotificationHistoryStore.HistoryEntry])) -> some View {
        let isMuted = group.entries.allSatisfy(\.muted)
        let appName = group.entries.first?.notification.appDisplayName ?? group.bundleID

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(appName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                if isMuted {
                    Text("· \(AppStrings.text(.notificationsRecordedWhileMuted, language: settings.interfaceLanguage)) · \(group.entries.count)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextSecondary.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)

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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .opacity(entry.muted ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.muted {
                Button("\(AppStrings.text(.notificationsAllowedApps, language: settings.interfaceLanguage)) · \(entry.notification.appDisplayName ?? entry.notification.bundleIdentifier)") {
                    var current = settings.notificationsWhitelistedBundleIDs
                    current.insert(entry.notification.bundleIdentifier)
                    settings.notificationsWhitelistedBundleIDs = current
                }
            }
        }
    }

    private func permissionsCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(12)
    }
}
