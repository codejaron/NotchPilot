import Darwin
import Dispatch
import Foundation
import OSLog
import SQLite3

private let observerLog = Logger(subsystem: "com.notchpilot.notifications", category: "DatabaseObserver")

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
    // Primary cursor: `rec_id` is the auto-increment PK, strictly monotonic with insertion
    // order. Used for normal polling so we never miss a row.
    private var lastSeenRowID: Int64 = 0
    // Secondary cursor: `delivered_date` (Mac absolute time). Only used during the one-shot
    // catch-up after the DB file is replaced (rec_id space gets renumbered there).
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
        lastSeenRowID = 0
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
    ///
    /// The new file has its own rec_id space (renumbered by VACUUM/recreation), so we
    /// can't reuse the old `lastSeenRowID`. Strategy:
    ///   1. Snapshot the new DB's MAX(rec_id) → `currentMax`.
    ///   2. Catch up via `delivered_date > lastSeenDeliveredAt AND rec_id <= currentMax`.
    ///   3. Set `lastSeenRowID = currentMax` so normal rec_id-based polling resumes
    ///      without re-emitting anything from step 2 and without skipping rows that
    ///      land after the snapshot.
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

        // Reset rec_id cursor — the new file's rec_id space is unrelated to the old one.
        lastSeenRowID = 0

        guard let currentMax = queryMaxRowID() else {
            needsReopen = true
            return
        }

        if let catchup = fetchCatchupAfterReopen(maxRowIDInclusive: currentMax) {
            if catchup.isEmpty == false {
                onNotifications?(catchup)
            }
        } else {
            needsReopen = true
            return
        }

        // Re-anchor rec_id cursor to the snapshot point. Anything inserted after the
        // snapshot has rec_id > currentMax and will be caught by the next normal poll.
        if currentMax > lastSeenRowID {
            lastSeenRowID = currentMax
        }

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
        let sql = "SELECT COALESCE(MAX(rec_id), 0), COALESCE(MAX(delivered_date), 0) FROM record;"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            lastSeenRowID = sqlite3_column_int64(stmt, 0)
            lastSeenDeliveredAt = sqlite3_column_double(stmt, 1)
        }
    }

    /// Queries the current MAX(rec_id). Returns nil on failure.
    private func queryMaxRowID() -> Int64? {
        guard let handle = dbHandle else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COALESCE(MAX(rec_id), 0) FROM record;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    /// Normal-path fetch: pulls every row with `rec_id > lastSeenRowID`.
    /// rec_id is strictly monotonic with insertion order, so this can't skip rows even
    /// when `delivered_date` is out-of-order (e.g. scheduled / replayed notifications).
    /// Returns `nil` on SQL failure (signals caller to reopen).
    private func fetchNewNotifications() -> [SystemNotification]? {
        guard let handle = dbHandle else { return nil }

        var stmt: OpaquePointer?
        let sql = "SELECT rec_id, app_id, data, delivered_date FROM record WHERE rec_id > ? ORDER BY rec_id ASC;"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, lastSeenRowID)

        return collectRows(from: stmt)
    }

    /// Catch-up fetch after a DB file replacement: rec_id space is renumbered in the new
    /// file, so we filter by `delivered_date` instead. Bounded by `maxRowIDInclusive` so
    /// the rec_id cursor we set after this can't miss rows inserted during the window.
    private func fetchCatchupAfterReopen(maxRowIDInclusive: Int64) -> [SystemNotification]? {
        guard let handle = dbHandle else { return nil }

        var stmt: OpaquePointer?
        let sql = """
            SELECT rec_id, app_id, data, delivered_date FROM record \
            WHERE delivered_date > ? AND rec_id <= ? \
            ORDER BY rec_id ASC;
            """
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, lastSeenDeliveredAt)
        sqlite3_bind_int64(stmt, 2, maxRowIDInclusive)

        return collectRows(from: stmt)
    }

    /// Steps the prepared statement and materializes rows.
    ///
    /// Cursors are advanced **transactionally**: we accumulate the candidate max values
    /// in locals, and only commit them to the instance properties after the loop
    /// completes successfully. On a mid-iteration `sqlite3_step` error we return `nil`
    /// and the cursor stays where it was — so the next reopen's `delivered_date`
    /// catch-up can re-fetch any rows we'd already pulled in this aborted batch.
    ///
    /// A row is emitted as long as we can resolve a `bundleIdentifier` from either:
    ///   1. the `app` join table (preferred — it's the macOS source of truth), or
    ///   2. the decoded plist payload (fallback for never-seen `app_id` values).
    /// Empty/garbage payloads still produce a `SystemNotification` (with nil content)
    /// rather than being silently dropped — missing a real notification is a worse
    /// outcome than surfacing an empty-content one.
    private func collectRows(from stmt: OpaquePointer?) -> [SystemNotification]? {
        var results: [SystemNotification] = []
        var pendingMaxRowID = lastSeenRowID
        var pendingMaxDelivered = lastSeenDeliveredAt
        var refreshedAppTable = false

        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            if step != SQLITE_ROW {
                observerLog.error("sqlite3_step failed mid-iteration: code=\(step, privacy: .public); cursor preserved")
                return nil
            }

            let recID = sqlite3_column_int64(stmt, 0)
            let appID = sqlite3_column_int64(stmt, 1)
            let dataLength = Int(sqlite3_column_bytes(stmt, 2))
            let blobPtr = sqlite3_column_blob(stmt, 2)
            let deliveredAbs = sqlite3_column_double(stmt, 3)

            if recID > pendingMaxRowID { pendingMaxRowID = recID }
            if deliveredAbs > pendingMaxDelivered { pendingMaxDelivered = deliveredAbs }

            // 1) Bundle resolution. Prefer the `app` join table.
            var bundle = bundleIDByAppID[appID]
            if bundle == nil && refreshedAppTable == false {
                // A brand-new app may have inserted both its `app` row and `record` row
                // since our last refresh. Reload once per batch and retry the lookup.
                loadAppIDTable()
                refreshedAppTable = true
                bundle = bundleIDByAppID[appID]
            }

            // 2) Best-effort content decode. Failure here is non-fatal.
            var decoded: NotificationPayloadDecoder.DecodedPayload?
            if let blobPtr, dataLength > 0 {
                let data = Data(bytes: blobPtr, count: dataLength)
                decoded = decoder.decode(payload: data)
            }

            // 3) If still no bundle, accept the decoder's bundleIdentifier as a last
            //    resort. Only drop when literally no source can name the app.
            let resolvedBundle = bundle ?? decoded?.bundleIdentifier
            guard let resolvedBundle else {
                observerLog.notice(
                    "dropping row rec_id=\(recID, privacy: .public) app_id=\(appID, privacy: .public) — no bundle from app table or payload (dataLength=\(dataLength, privacy: .public))"
                )
                continue
            }

            if decoded == nil {
                observerLog.info(
                    "emitting rec_id=\(recID, privacy: .public) bundle=\(resolvedBundle, privacy: .public) with empty content (payload undecodable, dataLength=\(dataLength, privacy: .public))"
                )
            }

            let deliveredAt = Date(timeIntervalSinceReferenceDate: deliveredAbs)

            results.append(
                SystemNotification(
                    dbRecordID: recID,
                    bundleIdentifier: resolvedBundle,
                    appDisplayName: nil,
                    title: decoded?.title,
                    subtitle: decoded?.subtitle,
                    body: decoded?.body,
                    deliveredAt: deliveredAt
                )
            )
        }

        // Commit cursor updates only after a fully successful iteration.
        lastSeenRowID = pendingMaxRowID
        lastSeenDeliveredAt = pendingMaxDelivered
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
            observerLog.debug("emitting batch of \(newOnes.count, privacy: .public) notification(s)")
            onNotifications?(newOnes)
        }
        emitState(.running(lastEventAt: Date()))
    }

    // MARK: State

    private func emitState(_ state: NotificationsPluginRuntimeState) {
        onStateChange?(state)
    }
}
