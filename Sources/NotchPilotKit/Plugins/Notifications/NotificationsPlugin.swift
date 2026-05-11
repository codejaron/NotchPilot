import AppKit
import Combine
import SwiftUI

@MainActor
public final class NotificationsPlugin: NotchPlugin {
    public let id = "notifications"
    public let title = "Notifications"
    public let iconSystemName = "bell.badge"
    public let accentColor: Color = NotchPilotTheme.notifications
    public let dockOrder = 95
    public let previewPriority: Int? = 150

    @Published public var isEnabled: Bool
    @Published public private(set) var runtimeState: NotificationsPluginRuntimeState = .disabled
    @Published public private(set) var diagnostics: NotificationsRuntimeDiagnostics = NotificationsRuntimeDiagnostics()

    public let historyStore: NotificationHistoryStore

    private let observer: NotificationDatabaseObserving
    private let appDirectory: NotificationAppDirectory
    private let settingsStore: SettingsStore
    private let nowProvider: @Sendable () -> Date
    private var burst: NotificationsSneakBurst
    private var settingsCancellables: Set<AnyCancellable> = []
    private weak var bus: EventBus?
    private var activeSneakPeekID: UUID?

    public convenience init() {
        self.init(
            observer: LiveNotificationDatabaseObserver(),
            settingsStore: .shared
        )
    }

    init(
        observer: NotificationDatabaseObserving,
        settingsStore: SettingsStore = .shared,
        appDirectory: NotificationAppDirectory = NotificationAppDirectory(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.observer = observer
        self.settingsStore = settingsStore
        self.appDirectory = appDirectory
        self.nowProvider = nowProvider
        self.burst = NotificationsSneakBurst(windowDuration: 1.0)
        self.historyStore = NotificationHistoryStore(limit: settingsStore.notificationsHistoryLimit)
        self.isEnabled = settingsStore.notificationsEnabled

        // Wire observer callbacks; hop to main actor (synchronously if already there).
        observer.onNotifications = { [weak self] ns in
            Self.performOnMainActor { [weak self] in
                self?.ingest(ns)
            }
        }
        observer.onStateChange = { [weak self] state in
            Self.performOnMainActor { [weak self] in
                self?.runtimeState = state
            }
        }
        observer.onKnownAppsLoaded = { [weak self] bundleIDs in
            Self.performOnMainActor { [weak self] in
                self?.handleKnownAppsLoaded(bundleIDs)
            }
        }
        observer.onDatabasePathResolved = { [weak self] path in
            Self.performOnMainActor { [weak self] in
                guard let self else { return }
                self.diagnostics = NotificationsRuntimeDiagnostics(
                    databasePath: path,
                    knownAppCount: self.diagnostics.knownAppCount,
                    ingestedRecordCount: self.diagnostics.ingestedRecordCount,
                    lastIngestAt: self.diagnostics.lastIngestAt
                )
            }
        }

        observeSettings()
    }

    nonisolated private static func performOnMainActor(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                action()
            }
            return
        }
        Task { @MainActor in
            action()
        }
    }

    public func preview(context: NotchContext) -> NotchPluginPreview? {
        guard isEnabled,
              settingsStore.notificationsSneakPreviewEnabled,
              settingsStore.activitySneakPreviewsHidden == false,
              case .running = runtimeState,
              let latest = historyStore.entries.first(where: { !$0.muted }) else {
            return nil
        }

        let notification = latest.notification
        let appName = notification.appDisplayName ?? notification.bundleIdentifier

        // Privacy-aware content extraction. Filter rules have already redacted the value:
        // .full:        title set, body set        → titleLine = title, bodyLine = body, extension
        // .senderOnly:  title set, body/subtitle nil → titleLine = title, bodyLine = nil,  extension (1 line)
        // .hidden:      title nil, subtitle nil, body nil → no extension; just app name on right
        let titleLine = notification.title ?? notification.subtitle
        let bodyLine = notification.body

        // Count contemporaries from the same app within the burst window for the badge.
        let burstWindow: TimeInterval = 1.0
        let cutoff = notification.deliveredAt.addingTimeInterval(-burstWindow)
        let burstCount = historyStore.entries.filter {
            $0.muted == false
                && $0.notification.bundleIdentifier == notification.bundleIdentifier
                && $0.notification.deliveredAt >= cutoff
        }.count

        let cameraClearance = context.notchGeometry.compactSize.width
        let notchHeight = context.notchGeometry.compactSize.height
        let leftFrameWidth = NotificationsCompactPreviewLayout.leftFrameWidth(burstCount: burstCount)
        let rightFrameWidth = NotificationsCompactPreviewLayout.rightFrameWidth(forAppName: appName)
        let totalWidth = NotificationsCompactPreviewLayout.totalWidth(
            compactWidth: cameraClearance,
            leftFrameWidth: leftFrameWidth,
            rightFrameWidth: rightFrameWidth
        )
        let extensionHeight = NotificationsCompactPreviewLayout.extensionHeight(
            hasTitle: (titleLine?.isEmpty == false),
            hasBody: (bodyLine?.isEmpty == false)
        )

        return NotchPluginPreview(
            width: totalWidth,
            height: notchHeight + extensionHeight,
            view: AnyView(
                NotificationsCompactPreview(
                    appDisplayName: appName,
                    titleLine: titleLine,
                    bodyLine: bodyLine,
                    burstCount: burstCount,
                    cameraClearanceWidth: cameraClearance,
                    notchHeight: notchHeight,
                    leftFrameWidth: leftFrameWidth,
                    rightFrameWidth: rightFrameWidth,
                    totalWidth: totalWidth,
                    extensionHeight: extensionHeight,
                    accentColor: accentColor
                )
            )
        )
    }

    public func contentView(context: NotchContext) -> AnyView {
        AnyView(
            NotificationsDashboardView(
                store: historyStore,
                runtimeState: runtimeState,
                diagnostics: diagnostics,
                accentColor: accentColor,
                onLaunch: { [weak self] bundleID in
                    self?.launchApp(bundleID: bundleID)
                }
            )
        )
    }

    private func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    public func activate(bus: EventBus) {
        self.bus = bus
        guard isEnabled else {
            runtimeState = .disabled
            return
        }
        observer.start()
    }

    public func deactivate() {
        observer.stop()
        burst.reset()
        if let id = activeSneakPeekID {
            bus?.emit(.dismissSneakPeek(requestID: id, target: .allScreens))
            activeSneakPeekID = nil
        }
        bus = nil
    }

    // MARK: - Ingest

    private func ingest(_ notifications: [SystemNotification]) {
        let rules = currentRules()

        for notification in notifications {
            let enriched = enrich(notification)
            updateKnownAppsCache(for: enriched)

            switch rules.evaluate(enriched) {
            case .drop:
                continue
            case .recordOnly(let redacted):
                historyStore.append(redacted, muted: true)
            case .present(let redacted):
                historyStore.append(redacted, muted: false)
                if settingsStore.notificationsSneakPreviewEnabled {
                    emitSneakPeek(for: redacted)
                }
            }
        }

        if !notifications.isEmpty {
            diagnostics = NotificationsRuntimeDiagnostics(
                databasePath: diagnostics.databasePath,
                knownAppCount: diagnostics.knownAppCount,
                ingestedRecordCount: diagnostics.ingestedRecordCount + notifications.count,
                lastIngestAt: Date()
            )
        }
    }

    private func handleKnownAppsLoaded(_ bundleIDs: [String]) {
        var current = settingsStore.notificationsKnownAppsCache
        var added = 0
        for bundleID in bundleIDs {
            if current[bundleID] != nil { continue }
            let meta = appDirectory.resolve(bundleIdentifier: bundleID)
            let displayName = meta?.displayName ?? bundleID
            current[bundleID] = KnownApp(
                bundleIdentifier: bundleID,
                displayName: displayName,
                iconCachePath: nil
            )
            added += 1
        }
        if added > 0 {
            settingsStore.notificationsKnownAppsCache = current
        }
        diagnostics = NotificationsRuntimeDiagnostics(
            databasePath: diagnostics.databasePath,
            knownAppCount: bundleIDs.count,
            ingestedRecordCount: diagnostics.ingestedRecordCount,
            lastIngestAt: diagnostics.lastIngestAt
        )
    }

    private func enrich(_ n: SystemNotification) -> SystemNotification {
        if n.appDisplayName != nil { return n }
        let meta = appDirectory.resolve(bundleIdentifier: n.bundleIdentifier)
        return SystemNotification(
            id: n.id, dbRecordID: n.dbRecordID,
            bundleIdentifier: n.bundleIdentifier,
            appDisplayName: meta?.displayName,
            title: n.title, subtitle: n.subtitle, body: n.body,
            deliveredAt: n.deliveredAt
        )
    }

    private func updateKnownAppsCache(for n: SystemNotification) {
        guard settingsStore.notificationsKnownAppsCache[n.bundleIdentifier] == nil else {
            return
        }
        let entry = KnownApp(
            bundleIdentifier: n.bundleIdentifier,
            displayName: n.appDisplayName ?? n.bundleIdentifier,
            iconCachePath: nil
        )
        var current = settingsStore.notificationsKnownAppsCache
        current[n.bundleIdentifier] = entry
        settingsStore.notificationsKnownAppsCache = current
    }

    private func currentRules() -> NotificationFilterRules {
        NotificationFilterRules(
            enabled: settingsStore.notificationsEnabled,
            whitelistedBundleIDs: settingsStore.notificationsWhitelistedBundleIDs,
            respectSystemDND: settingsStore.notificationsRespectSystemDND,
            contentPrivacy: settingsStore.notificationsContentPrivacy,
            isSystemDNDActive: { false } // System DND detection deferred to a future task.
        )
    }

    private func emitSneakPeek(for n: SystemNotification) {
        // Track burst window for the badge count surfaced in preview().
        _ = burst.observe(n, now: nowProvider())

        // Always dismiss the previous active SneakPeek and emit a fresh one so that:
        //   - Same-app rapid messages each get their own brief banner (with updating badge).
        //   - Cross-app messages take over the banner instead of queueing behind a stale one.
        // The 3.5 s autoDismiss starts over each emit, so a continuous stream stays visible.
        if let previousID = activeSneakPeekID {
            bus?.emit(.dismissSneakPeek(requestID: previousID, target: .allScreens))
        }

        let request = SneakPeekRequest(
            pluginID: id,
            priority: SneakPeekRequestPriority.notifications,
            target: .activeScreen,
            kind: .attention,
            isInteractive: false,
            autoDismissAfter: 3.5
        )
        activeSneakPeekID = request.id
        bus?.emit(.sneakPeekRequested(request))
    }

    // MARK: - Settings reactivity

    private func observeSettings() {
        settingsStore.$notificationsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.handleEnabledChange(enabled)
            }
            .store(in: &settingsCancellables)
    }

    private func handleEnabledChange(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            guard bus != nil else { return }
            observer.start()
        } else {
            observer.stop()
            historyStore.clear()
            burst.reset()
            runtimeState = .disabled
            diagnostics = NotificationsRuntimeDiagnostics()
        }
    }
}
