import Darwin
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
    // Cursor is the Mac-absolute `delivered_date` of the most recent emitted notification.
    // Using a time-based cursor (rather than `rec_id`) keeps us correct across
    // usernoted's periodic VACUUM / file replacement, where rec_id space is renumbered.
    private var lastSeenDeliveredAt: Double = 0
    private var pollTimer: DispatchSourceTimer?
    private let pollInterval: DispatchTimeInterval = .seconds(2)
    private var databaseURL: URL?

    // Watches the DB file inode. When usernoted replaces the file (rename/delete),
    // our open SQLite handle keeps reading the orphaned inode and silently goes blind.
    // The monitor flips `needsReopen` so the next poll cycle reopens the connection.
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var monitoredFD: CInt = -1
    private var needsReopen: Bool = false

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
        if monitoredFD != -1 {
            close(monitoredFD)
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
        guard openDatabase() else { return }
        loadAppIDTable()
        let bundleIDs = Array(bundleIDByAppID.values).sorted()
        onKnownAppsLoaded?(bundleIDs)
        seedBaselineCursor()
        startFileMonitor()
        startPolling()
        emitState(.running(lastEventAt: nil))
    }

    private func stopInternal() {
        pollTimer?.cancel()
        pollTimer = nil

        stopFileMonitor()
        closeDatabase()
        bundleIDByAppID.removeAll()
        lastSeenDeliveredAt = 0
        databaseURL = nil
        needsReopen = false
    }

    // MARK: Database open/close

    /// Opens the database and emits the appropriate state if it fails.
    /// Returns true on success.
    private func openDatabase() -> Bool {
        guard let url = locator.locateDatabase() else {
            onDatabasePathResolved?(nil)
            emitState(.databaseNotFound)
            return false
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
            return false
        }
        dbHandle = handle
        return true
    }

    private func closeDatabase() {
        if let handle = dbHandle {
            sqlite3_close(handle)
            dbHandle = nil
        }
    }

    /// Reopens the database after the file was replaced (or queries started failing).
    /// Preserves `lastSeenDeliveredAt` so the next fetch catches any notifications
    /// that arrived around the swap.
    private func reopenDatabase() {
        needsReopen = false
        stopFileMonitor()
        closeDatabase()
        bundleIDByAppID.removeAll()

        guard openDatabase() else {
            // Stay flagged so the next poll retries.
            needsReopen = true
            return
        }
        loadAppIDTable()
        let bundleIDs = Array(bundleIDByAppID.values).sorted()
        onKnownAppsLoaded?(bundleIDs)
        startFileMonitor()
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

    private func seedBaselineCursor() {
        guard let handle = dbHandle else { return }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COALESCE(MAX(delivered_date), 0) FROM record;", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            lastSeenDeliveredAt = sqlite3_column_double(stmt, 0)
        }
    }

    /// Returns `nil` on SQL failure (signals caller to reopen). Empty array means no new rows.
    private func fetchNewNotifications() -> [SystemNotification]? {
        guard let handle = dbHandle else { return nil }

        var stmt: OpaquePointer?
        let sql = "SELECT rec_id, app_id, data, delivered_date FROM record WHERE delivered_date > ? ORDER BY delivered_date ASC, rec_id ASC;"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, lastSeenDeliveredAt)

        var results: [SystemNotification] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            if step != SQLITE_ROW { return nil }

            let recID = sqlite3_column_int64(stmt, 0)
            let appID = sqlite3_column_int64(stmt, 1)
            let dataLength = Int(sqlite3_column_bytes(stmt, 2))
            let blobPtr = sqlite3_column_blob(stmt, 2)
            let deliveredAbs = sqlite3_column_double(stmt, 3)

            if deliveredAbs > lastSeenDeliveredAt {
                lastSeenDeliveredAt = deliveredAbs
            }

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

    // MARK: File monitoring

    private func startFileMonitor() {
        stopFileMonitor()
        guard let url = databaseURL else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else { return }
        monitoredFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.needsReopen = true
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.monitoredFD != -1 {
                close(self.monitoredFD)
                self.monitoredFD = -1
            }
        }
        source.resume()
        fileMonitor = source
    }

    private func stopFileMonitor() {
        fileMonitor?.cancel()
        fileMonitor = nil
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
        if needsReopen {
            reopenDatabase()
            // If reopen failed (e.g. file not yet present mid-rename), bail and retry next tick.
            if needsReopen { return }
        }

        guard let newOnes = fetchNewNotifications() else {
            // Query failed — handle is likely stale. Flag for reopen on the next tick.
            needsReopen = true
            return
        }

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
