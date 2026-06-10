import Darwin
import XCTest
@testable import NotchPilotKit

final class MediaStreamProcessReaperTests: XCTestCase {
    func testTerminatesCapturedProcessBeforeReturning() {
        let process = TestMediaStreamProcess(pid: 4241, exitsOnTerminate: false)
        let queue = DispatchQueue(label: "MediaStreamProcessReaperTests.suspended")
        queue.suspend()
        let reaper = MediaStreamProcessReaper(
            timeout: 0.01,
            pollInterval: 0.001,
            queue: queue,
            killProcess: { _, _ in 0 },
            log: { _ in }
        )

        reaper.reap(process)

        XCTAssertEqual(process.terminateCount, 1)

        process.markExited()
        queue.resume()
        queue.sync {}
    }

    func testForceKillsCapturedProcessWhenTerminateTimesOut() {
        let process = TestMediaStreamProcess(pid: 4242, exitsOnTerminate: false)
        let queue = DispatchQueue(label: "MediaStreamProcessReaperTests.timeout")
        let killRecord = KillRecord()
        let reaper = MediaStreamProcessReaper(
            timeout: 0.01,
            pollInterval: 0.001,
            queue: queue,
            killProcess: { pid, signal in
                killRecord.record(pid: pid, signal: signal)
                process.markExited()
                return 0
            },
            log: { _ in }
        )

        reaper.reap(process)

        XCTAssertEqual(killRecord.wait(), .success)
        queue.sync {}

        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(process.waitCount, 1)
        XCTAssertEqual(killRecord.pid, process.processIdentifier)
        XCTAssertEqual(killRecord.signal, SIGKILL)
    }

    func testDoesNotForceKillProcessThatExitsAfterTerminate() {
        let process = TestMediaStreamProcess(pid: 4243, exitsOnTerminate: true)
        let queue = DispatchQueue(label: "MediaStreamProcessReaperTests.clean-exit")
        let killRecord = KillRecord()
        let reaper = MediaStreamProcessReaper(
            timeout: 0.01,
            pollInterval: 0.001,
            queue: queue,
            killProcess: { pid, signal in
                killRecord.record(pid: pid, signal: signal)
                return 0
            },
            log: { _ in }
        )

        reaper.reap(process)
        queue.sync {}

        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(process.waitCount, 1)
        XCTAssertNil(killRecord.pid)
        XCTAssertNil(killRecord.signal)
    }

    func testReapReturnsBeforeTimedOutProcessFinishesCleanup() {
        let process = TestMediaStreamProcess(pid: 4244, exitsOnTerminate: false)
        let queue = DispatchQueue(label: "MediaStreamProcessReaperTests.async")
        let reaper = MediaStreamProcessReaper(
            timeout: 0.2,
            pollInterval: 0.01,
            queue: queue,
            killProcess: { _, _ in
                process.markExited()
                return 0
            },
            log: { _ in }
        )

        let start = Date()
        reaper.reap(process)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.05)
        queue.sync {}
    }
}

private final class TestMediaStreamProcess: MediaStreamProcessHandling, @unchecked Sendable {
    let processIdentifier: pid_t

    private let exitsOnTerminate: Bool
    private let lock = NSLock()
    private var running = true
    private var terminateCounter = 0
    private var waitCounter = 0

    init(pid: pid_t, exitsOnTerminate: Bool) {
        self.processIdentifier = pid
        self.exitsOnTerminate = exitsOnTerminate
    }

    var isRunning: Bool {
        locked { running }
    }

    var terminateCount: Int {
        locked { terminateCounter }
    }

    var waitCount: Int {
        locked { waitCounter }
    }

    func terminate() {
        locked {
            terminateCounter += 1
            if exitsOnTerminate {
                running = false
            }
        }
    }

    func waitUntilExit() {
        locked {
            waitCounter += 1
        }
    }

    func markExited() {
        locked {
            running = false
        }
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class KillRecord: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var recordedPID: pid_t?
    private var recordedSignal: Int32?

    var pid: pid_t? {
        locked { recordedPID }
    }

    var signal: Int32? {
        locked { recordedSignal }
    }

    func record(pid: pid_t, signal: Int32) {
        locked {
            recordedPID = pid
            recordedSignal = signal
        }
        semaphore.signal()
    }

    func wait() -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + 1)
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
