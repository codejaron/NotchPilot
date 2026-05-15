import Foundation

// MARK: - Privacy mode

public enum NotificationContentPrivacy: String, CaseIterable, Codable, Sendable {
    case full
    case senderOnly
    case hidden
}

// MARK: - Persisted "known app" cache entry

public enum KnownAppDiscoverySource: String, Codable, Sendable {
    case databasePreload
    case notificationArrival
}

public struct KnownApp: Codable, Equatable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String
    public let iconCachePath: String?
    public let discoverySource: KnownAppDiscoverySource

    public init(
        bundleIdentifier: String,
        displayName: String,
        iconCachePath: String?,
        discoverySource: KnownAppDiscoverySource = .databasePreload
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.iconCachePath = iconCachePath
        self.discoverySource = discoverySource
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case displayName
        case iconCachePath
        case discoverySource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.iconCachePath = try container.decodeIfPresent(String.self, forKey: .iconCachePath)
        self.discoverySource = try container.decodeIfPresent(
            KnownAppDiscoverySource.self,
            forKey: .discoverySource
        ) ?? .databasePreload
    }
}

// MARK: - System notification value

public struct SystemNotification: Equatable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let dbRecordID: Int64
    public let bundleIdentifier: String
    public let appDisplayName: String?
    public let title: String?
    public let subtitle: String?
    public let body: String?
    public let deliveredAt: Date

    public init(
        id: UUID = UUID(),
        dbRecordID: Int64,
        bundleIdentifier: String,
        appDisplayName: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        deliveredAt: Date
    ) {
        self.id = id
        self.dbRecordID = dbRecordID
        self.bundleIdentifier = bundleIdentifier
        self.appDisplayName = appDisplayName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.deliveredAt = deliveredAt
    }
}

// MARK: - Filter rules

public struct NotificationFilterRules: Sendable {
    public enum Decision: Equatable {
        case drop
        case recordOnly(redacted: SystemNotification)
        case present(redacted: SystemNotification)
    }

    public let enabled: Bool
    public let whitelistedBundleIDs: Set<String>
    public let respectSystemDND: Bool
    public let contentPrivacy: NotificationContentPrivacy
    public let isSystemDNDActive: @Sendable () -> Bool

    public init(
        enabled: Bool,
        whitelistedBundleIDs: Set<String>,
        respectSystemDND: Bool,
        contentPrivacy: NotificationContentPrivacy,
        isSystemDNDActive: @escaping @Sendable () -> Bool
    ) {
        self.enabled = enabled
        self.whitelistedBundleIDs = whitelistedBundleIDs
        self.respectSystemDND = respectSystemDND
        self.contentPrivacy = contentPrivacy
        self.isSystemDNDActive = isSystemDNDActive
    }

    public func evaluate(_ notification: SystemNotification) -> Decision {
        guard enabled else { return .drop }

        guard whitelistedBundleIDs.contains(notification.bundleIdentifier) else {
            return .drop
        }

        let redacted = redact(notification)
        let isDND = respectSystemDND && isSystemDNDActive()

        if isDND {
            return .recordOnly(redacted: redacted)
        }
        return .present(redacted: redacted)
    }

    private func redact(_ n: SystemNotification) -> SystemNotification {
        switch contentPrivacy {
        case .full:
            return n
        case .senderOnly:
            return SystemNotification(
                id: n.id, dbRecordID: n.dbRecordID,
                bundleIdentifier: n.bundleIdentifier,
                appDisplayName: n.appDisplayName,
                title: n.title, subtitle: nil, body: nil,
                deliveredAt: n.deliveredAt
            )
        case .hidden:
            return SystemNotification(
                id: n.id, dbRecordID: n.dbRecordID,
                bundleIdentifier: n.bundleIdentifier,
                appDisplayName: n.appDisplayName,
                title: nil, subtitle: nil, body: nil,
                deliveredAt: n.deliveredAt
            )
        }
    }
}

// MARK: - Burst coalescer

public struct NotificationsSneakBurst: Sendable {
    public enum Result: Equatable {
        case emit(count: Int)
        case fold(count: Int)
    }

    public let windowDuration: TimeInterval
    private var openWindow: (bundleID: String, openedAt: Date, count: Int)?

    public init(windowDuration: TimeInterval = 1.0) {
        self.windowDuration = windowDuration
        self.openWindow = nil
    }

    public mutating func observe(_ notification: SystemNotification, now: Date) -> Result {
        if let window = openWindow,
           window.bundleID == notification.bundleIdentifier,
           now.timeIntervalSince(window.openedAt) <= windowDuration {
            let updatedCount = window.count + 1
            openWindow = (window.bundleID, window.openedAt, updatedCount)
            return .fold(count: updatedCount)
        }

        openWindow = (notification.bundleIdentifier, now, 1)
        return .emit(count: 1)
    }

    public mutating func reset() {
        openWindow = nil
    }
}

// MARK: - Runtime state

public enum NotificationsPluginRuntimeState: Equatable, Sendable {
    case disabled
    case awaitingFullDiskAccess
    case databaseNotFound
    case databaseUnreadable(message: String)
    case running(lastEventAt: Date?)
}

// MARK: - Runtime diagnostics

public struct NotificationsRuntimeDiagnostics: Equatable, Sendable {
    public let databasePath: String?
    public let knownAppCount: Int
    public let ingestedRecordCount: Int
    public let lastIngestAt: Date?

    public init(
        databasePath: String? = nil,
        knownAppCount: Int = 0,
        ingestedRecordCount: Int = 0,
        lastIngestAt: Date? = nil
    ) {
        self.databasePath = databasePath
        self.knownAppCount = knownAppCount
        self.ingestedRecordCount = ingestedRecordCount
        self.lastIngestAt = lastIngestAt
    }
}
