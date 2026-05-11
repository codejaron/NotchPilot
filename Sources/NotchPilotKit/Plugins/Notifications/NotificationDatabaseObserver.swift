import Dispatch
import Foundation
import SQLite3

public protocol NotificationDatabaseObserving: AnyObject {
    var onNotifications: ((@Sendable ([SystemNotification]) -> Void))? { get set }
    var onStateChange: ((@Sendable (NotificationsPluginRuntimeState) -> Void))? { get set }
    var onKnownAppsLoaded: ((@Sendable ([String]) -> Void))? { get set }
    var onDatabasePathResolved: ((@Sendable (String?) -> Void))? { get set }

    func start()
    func stop()
}

// `@unchecked Sendable`: all mutable state is confined to `queue` (a serial DispatchQueue).
// The compiler can't verify queue-isolation, so we vouch for it manually.
public final class LiveNotificationDatabaseObserver: NotificationDatabaseObserving, @unchecked Sendable {
    public var onNotifications: ((@Sendable ([SystemNotification]) -> Void))?
    public var onStateChange: ((@Sendable (NotificationsPluginRuntimeState) -> Void))?
    public var onKnownAppsLoaded: ((@Sendable ([String]) -> Void))?
    public var onDatabasePathResolved: ((@Sendable (String?) -> Void))?

    private let locator: NotificationDatabaseLocator
    private let decoder: NotificationPayloadDecoder
    private let queue = DispatchQueue(label: "NotchPilot.NotificationsObserver", qos: .utility)

    private var dbHandle: OpaquePointer?
    private var bundleIDByAppID: [Int64: String] = [:]
    private var lastSeenRowID: Int64 = 0
    private var pollTimer: DispatchSourceTimer?
    private let pollInterval: DispatchTimeInterval = .seconds(2)
    private var databaseURL: URL?

    public init(
        locator: NotificationDatabaseLocator = NotificationDatabaseLocator(),
        decoder: NotificationPayloadDecoder = NotificationPayloadDecoder()
    ) {
        self.locator = locator
        self.decoder = decoder
    }

    deinit {
        if let handle = dbHandle {
            sqlite3_close(handle)
        }
    }

    // MARK: Public API

    public func start() {
        queue.async { [weak self] in self?.startInternal() }
    }

    public func stop() {
        queue.async { [weak self] in self?.stopInternal() }
    }

    // MARK: Lifecycle (must be called on `queue`)

    private func startInternal() {
        guard let url = locator.locateDatabase() else {
            onDatabasePathResolved?(nil)
            emitState(.databaseNotFound)
            return
        }
        databaseURL = url
        onDatabasePathResolved?(url.path)

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        if openResult != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)

            // EACCES is the FDA signal. Other failures are surfaced as `databaseUnreadable`.
            if openResult == SQLITE_CANTOPEN || openResult == SQLITE_AUTH {
                emitState(.awaitingFullDiskAccess)
            } else {
                emitState(.databaseUnreadable(message: msg))
            }
            return
        }
        dbHandle = handle

        loadAppIDTable()
        let bundleIDs = Array(bundleIDByAppID.values).sorted()
        onKnownAppsLoaded?(bundleIDs)
        seedBaselineRowID()
        startPolling()
        emitState(.running(lastEventAt: nil))
    }

    private func stopInternal() {
        pollTimer?.cancel()
        pollTimer = nil

        if let handle = dbHandle {
            sqlite3_close(handle)
            dbHandle = nil
        }
        bundleIDByAppID.removeAll()
        lastSeenRowID = 0
        databaseURL = nil
    }

    // MARK: SQL helpers

    private func loadAppIDTable() {
        guard let handle = dbHandle else { return }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT app_id, identifier FROM app;", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let appID = sqlite3_column_int64(stmt, 0)
            guard let cString = sqlite3_column_text(stmt, 1) else { continue }
            bundleIDByAppID[appID] = String(cString: cString)
        }
    }

    private func seedBaselineRowID() {
        guard let handle = dbHandle else { return }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COALESCE(MAX(rec_id), 0) FROM record;", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            lastSeenRowID = sqlite3_column_int64(stmt, 0)
        }
    }

    private func fetchNewNotifications() -> [SystemNotification] {
        guard let handle = dbHandle else { return [] }

        var stmt: OpaquePointer?
        let sql = "SELECT rec_id, app_id, data, delivered_date FROM record WHERE rec_id > ? ORDER BY rec_id ASC;"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, lastSeenRowID)

        var results: [SystemNotification] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let recID = sqlite3_column_int64(stmt, 0)
            let appID = sqlite3_column_int64(stmt, 1)
            let dataLength = Int(sqlite3_column_bytes(stmt, 2))
            let blobPtr = sqlite3_column_blob(stmt, 2)
            let deliveredAbs = sqlite3_column_double(stmt, 3)

            lastSeenRowID = max(lastSeenRowID, recID)

            guard let blobPtr, dataLength > 0 else { continue }
            let data = Data(bytes: blobPtr, count: dataLength)

            // Mac absolute time → Date (seconds since 2001-01-01 UTC).
            let deliveredAt = Date(timeIntervalSinceReferenceDate: deliveredAbs)

            let bundleByAppRow = bundleIDByAppID[appID]
            guard let decoded = decoder.decode(payload: data) else { continue }
            let bundle = bundleByAppRow ?? decoded.bundleIdentifier

            results.append(
                SystemNotification(
                    dbRecordID: recID,
                    bundleIdentifier: bundle,
                    appDisplayName: nil,
                    title: decoded.title,
                    subtitle: decoded.subtitle,
                    body: decoded.body,
                    deliveredAt: deliveredAt
                )
            )
        }
        return results
    }

    // MARK: Polling

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.performFetch()
        }
        timer.resume()
        pollTimer = timer
    }

    private func performFetch() {
        let newOnes = fetchNewNotifications()
        if newOnes.isEmpty == false {
            onNotifications?(newOnes)
            // Refresh `app` mapping in case a new app was added since the last load.
            loadAppIDTable()
        }
        emitState(.running(lastEventAt: Date()))
    }

    // MARK: State

    private func emitState(_ state: NotificationsPluginRuntimeState) {
        onStateChange?(state)
    }
}
