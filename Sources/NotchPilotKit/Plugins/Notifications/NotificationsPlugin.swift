import AppKit
import Combine
import SwiftUI

@MainActor
public final class NotificationsPlugin: NotchPlugin {
    private struct PreviewBatch: Equatable {
        let bundleIdentifier: String
        var notificationIDs: [UUID]
    }

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
    private let sneakPeekAutoDismissDuration: TimeInterval
    private var settingsCancellables: Set<AnyCancellable> = []
    private weak var bus: EventBus?
    private var previewBatchesByRequestID: [UUID: PreviewBatch] = [:]
    private var previewBatchRequestOrder: [UUID] = []
    private var activeSneakPeekIDs: Set<UUID> = []
    private static let defaultSneakPeekAutoDismissDuration: TimeInterval = 2.0
    private static let burstWindowDuration: TimeInterval = 3.5
    private static let maxPreviewBatchSize = 3

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
        sneakPeekAutoDismissDuration: TimeInterval = NotificationsPlugin.defaultSneakPeekAutoDismissDuration
    ) {
        self.observer = observer
        self.settingsStore = settingsStore
        self.appDirectory = appDirectory
        self.sneakPeekAutoDismissDuration = sneakPeekAutoDismissDuration
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
        let visibleEntries = historyStore.entries.filter { !$0.muted }
        let previewEntries = currentPreviewEntries(
            from: visibleEntries,
            currentSneakPeek: context.currentSneakPeek
        )
        let hasCurrentRequestBatch = hasPreviewBatch(for: context.currentSneakPeek)
        guard isEnabled,
              settingsStore.notificationsSneakPreviewEnabled,
              settingsStore.activitySneakPreviewsHidden == false,
              (isRunning || hasCurrentRequestBatch),
              let latest = previewEntries.first else {
            return nil
        }

        let notification = latest.notification
        let appName = notification.appDisplayName ?? notification.bundleIdentifier

        let contentLines = previewEntries.compactMap {
            Self.compactPreviewLine(for: $0.notification)
        }
        let foldedCount = max(0, previewEntries.count - 1)

        let cameraClearance = context.notchGeometry.compactSize.width
        let notchHeight = context.notchGeometry.compactSize.height
        let leftFrameWidth = NotificationsCompactPreviewLayout.leftFrameWidth()
        let rightFrameWidth = NotificationsCompactPreviewLayout.rightFrameWidth(
            forAppName: appName,
            foldedCount: foldedCount
        )
        let totalWidth = NotificationsCompactPreviewLayout.totalWidth(
            compactWidth: cameraClearance,
            leftFrameWidth: leftFrameWidth,
            rightFrameWidth: rightFrameWidth
        )
        let extensionHeight = NotificationsCompactPreviewLayout.extensionHeight(for: contentLines)

        return NotchPluginPreview(
            width: totalWidth,
            height: notchHeight + extensionHeight,
            view: AnyView(
                NotificationsCompactPreview(
                    bundleIdentifier: notification.bundleIdentifier,
                    appDisplayName: appName,
                    contentLines: contentLines,
                    foldedCount: foldedCount,
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

    private var isRunning: Bool {
        if case .running = runtimeState {
            return true
        }
        return false
    }

    private func hasPreviewBatch(for currentSneakPeek: SneakPeekRequest?) -> Bool {
        guard currentSneakPeek?.pluginID == id,
              let requestID = currentSneakPeek?.id else {
            return false
        }

        return previewBatchesByRequestID[requestID] != nil
    }

    private func currentPreviewEntries(
        from visibleEntries: [NotificationHistoryStore.HistoryEntry],
        currentSneakPeek: SneakPeekRequest?
    ) -> [NotificationHistoryStore.HistoryEntry] {
        if currentSneakPeek?.pluginID == id,
           let requestID = currentSneakPeek?.id,
           let batch = previewBatchesByRequestID[requestID] {
            let batchIDs = Set(batch.notificationIDs)
            return visibleEntries
                .filter { batchIDs.contains($0.notification.id) }
                .sorted {
                    Self.isNewer($0.notification, than: $1.notification)
                }
        }

        guard let latest = visibleEntries.sorted(by: {
            Self.isNewer($0.notification, than: $1.notification)
        }).first else {
            return []
        }

        return Array(Self.burstEntries(
            from: visibleEntries,
            latest: latest.notification,
            windowDuration: Self.burstWindowDuration
        ).prefix(Self.maxPreviewBatchSize))
    }

    private static func burstEntries(
        from entries: [NotificationHistoryStore.HistoryEntry],
        latest: SystemNotification,
        windowDuration: TimeInterval
    ) -> [NotificationHistoryStore.HistoryEntry] {
        let cutoff = latest.deliveredAt.addingTimeInterval(-windowDuration)
        return entries
            .filter {
                $0.notification.bundleIdentifier == latest.bundleIdentifier
                    && $0.notification.deliveredAt >= cutoff
            }
            .sorted {
                isNewer($0.notification, than: $1.notification)
            }
    }

    private static func compactPreviewLine(for notification: SystemNotification) -> NotificationsCompactPreviewLine? {
        let title = cleaned(notification.title ?? notification.subtitle)
        let body = cleaned(notification.body)

        guard title != nil || body != nil else {
            return nil
        }

        return NotificationsCompactPreviewLine(title: title, body: body)
    }

    private static func isNewer(_ lhs: SystemNotification, than rhs: SystemNotification) -> Bool {
        if lhs.deliveredAt == rhs.deliveredAt {
            return lhs.dbRecordID > rhs.dbRecordID
        }

        return lhs.deliveredAt > rhs.deliveredAt
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        dismissActiveSneakPeeks()
        clearPreviewBatches()
        bus = nil
    }

    // MARK: - Ingest

    private func ingest(_ notifications: [SystemNotification]) {
        let rules = currentRules()
        var previewNotifications: [SystemNotification] = []

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
                    previewNotifications.append(redacted)
                }
            }
        }

        if previewNotifications.isEmpty == false {
            emitSneakPeeks(for: previewNotifications)
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
        let current = settingsStore.notificationsKnownAppsCache
        let whitelistedBundleIDs = settingsStore.notificationsWhitelistedBundleIDs
        var next: [String: KnownApp] = [:]

        for bundleID in bundleIDs {
            guard Self.shouldIncludePreloadedKnownApp(bundleIdentifier: bundleID) else {
                continue
            }

            if let meta = appDirectory.resolve(bundleIdentifier: bundleID) {
                next[bundleID] = knownAppEntry(
                    bundleIdentifier: bundleID,
                    displayName: meta.displayName,
                    cached: current[bundleID],
                    discoverySource: current[bundleID]?.discoverySource ?? .databasePreload
                )
            } else if let cached = current[bundleID],
                      shouldKeepUnresolvedKnownApp(cached, whitelistedBundleIDs: whitelistedBundleIDs) {
                next[bundleID] = cached
            }
        }

        for (bundleID, cached) in current where next[bundleID] == nil {
            guard Self.shouldIncludePreloadedKnownApp(bundleIdentifier: bundleID) else {
                continue
            }

            if let meta = appDirectory.resolve(bundleIdentifier: bundleID) {
                next[bundleID] = knownAppEntry(
                    bundleIdentifier: bundleID,
                    displayName: meta.displayName,
                    cached: cached,
                    discoverySource: cached.discoverySource
                )
            } else if shouldKeepUnresolvedKnownApp(cached, whitelistedBundleIDs: whitelistedBundleIDs) {
                next[bundleID] = cached
            }
        }

        if next != current {
            settingsStore.notificationsKnownAppsCache = next
        }
        diagnostics = NotificationsRuntimeDiagnostics(
            databasePath: diagnostics.databasePath,
            knownAppCount: next.count,
            ingestedRecordCount: diagnostics.ingestedRecordCount,
            lastIngestAt: diagnostics.lastIngestAt
        )
    }

    private func knownAppEntry(
        bundleIdentifier: String,
        displayName: String,
        cached: KnownApp?,
        discoverySource: KnownAppDiscoverySource
    ) -> KnownApp {
        KnownApp(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            iconCachePath: cached?.iconCachePath,
            discoverySource: discoverySource
        )
    }

    private static func shouldIncludePreloadedKnownApp(bundleIdentifier: String) -> Bool {
        let lowercased = bundleIdentifier.lowercased()
        return lowercased != "com.apple.background-service"
    }

    private func shouldKeepUnresolvedKnownApp(
        _ app: KnownApp,
        whitelistedBundleIDs: Set<String>
    ) -> Bool {
        app.discoverySource == .notificationArrival
            || whitelistedBundleIDs.contains(app.bundleIdentifier)
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
        let existing = settingsStore.notificationsKnownAppsCache[n.bundleIdentifier]
        let entry = KnownApp(
            bundleIdentifier: n.bundleIdentifier,
            displayName: n.appDisplayName ?? existing?.displayName ?? n.bundleIdentifier,
            iconCachePath: existing?.iconCachePath,
            discoverySource: .notificationArrival
        )

        guard existing != entry else {
            return
        }

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

    private func emitSneakPeeks(for notifications: [SystemNotification]) {
        for batch in Self.previewBatches(from: notifications) {
            emitPreviewBatch(batch)
        }
        prunePreviewBatchCache()
    }

    private static func previewBatches(from notifications: [SystemNotification]) -> [PreviewBatch] {
        var batches: [PreviewBatch] = []
        var current: PreviewBatch?

        for notification in notifications {
            if var batch = current,
               batch.bundleIdentifier == notification.bundleIdentifier,
               batch.notificationIDs.count < maxPreviewBatchSize {
                batch.notificationIDs.append(notification.id)
                current = batch
                continue
            }

            if let current {
                batches.append(current)
            }
            current = PreviewBatch(
                bundleIdentifier: notification.bundleIdentifier,
                notificationIDs: [notification.id]
            )
        }

        if let current {
            batches.append(current)
        }

        return batches
    }

    private func emitPreviewBatch(_ batch: PreviewBatch) {
        let request = SneakPeekRequest(
            pluginID: id,
            priority: SneakPeekRequestPriority.notifications,
            target: .activeScreen,
            kind: .attention,
            isInteractive: false,
            autoDismissAfter: sneakPeekAutoDismissDuration
        )
        previewBatchesByRequestID[request.id] = batch
        previewBatchRequestOrder.append(request.id)
        activeSneakPeekIDs.insert(request.id)
        bus?.emit(.sneakPeekRequested(request))
    }

    private func dismissActiveSneakPeeks() {
        for requestID in activeSneakPeekIDs {
            bus?.emit(.dismissSneakPeek(requestID: requestID, target: .allScreens))
        }
        activeSneakPeekIDs.removeAll()
    }

    private func clearPreviewBatches() {
        previewBatchesByRequestID.removeAll()
        previewBatchRequestOrder.removeAll()
    }

    private func prunePreviewBatchCache() {
        let maxCachedRequests = max(20, historyStore.limit)
        guard previewBatchRequestOrder.count > maxCachedRequests else {
            return
        }

        let overflow = previewBatchRequestOrder.count - maxCachedRequests
        let expiredRequestIDs = previewBatchRequestOrder.prefix(overflow)
        for requestID in expiredRequestIDs {
            previewBatchesByRequestID.removeValue(forKey: requestID)
            activeSneakPeekIDs.remove(requestID)
        }
        previewBatchRequestOrder.removeFirst(overflow)
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
            dismissActiveSneakPeeks()
            clearPreviewBatches()
            runtimeState = .disabled
            diagnostics = NotificationsRuntimeDiagnostics()
        }
    }
}
