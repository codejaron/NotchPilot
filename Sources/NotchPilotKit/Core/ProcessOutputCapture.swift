import Foundation

struct CapturedProcessOutput: Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

enum ProcessOutputCapture {
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> CapturedProcessOutput? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let terminationObserver = ProcessTerminationObserver()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            terminationObserver.finish()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputBuffer = ProcessOutputBuffer()
        let errorBuffer = ProcessOutputBuffer()
        let drainGroup = DispatchGroup()
        drain(pipe: outputPipe, into: outputBuffer, group: drainGroup)
        drain(pipe: errorPipe, into: errorBuffer, group: drainGroup)

        if terminationObserver.wait(timeout: timeout) == false {
            terminate(process, terminationObserver: terminationObserver)
        }

        _ = drainGroup.wait(timeout: .now() + 1)
        process.terminationHandler = nil
        return CapturedProcessOutput(
            terminationStatus: process.terminationStatus,
            standardOutput: outputBuffer.value,
            standardError: errorBuffer.value
        )
    }

    static func runAsync(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async -> CapturedProcessOutput? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let terminationObserver = ProcessTerminationObserver()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            terminationObserver.finish()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        async let standardOutput = readData(from: outputPipe)
        async let standardError = readData(from: errorPipe)

        if await terminationObserver.waitAsync(timeout: timeout) == false {
            await terminateAsync(process, terminationObserver: terminationObserver)
        }

        let capturedOutput = await standardOutput
        let capturedError = await standardError
        process.terminationHandler = nil
        return CapturedProcessOutput(
            terminationStatus: process.terminationStatus,
            standardOutput: capturedOutput,
            standardError: capturedError
        )
    }

    private static func drain(
        pipe: Pipe,
        into buffer: ProcessOutputBuffer,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            buffer.set(pipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
    }

    private static func readData(from pipe: Pipe) async -> Data {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }

    private static func terminate(
        _ process: Process,
        terminationObserver: ProcessTerminationObserver
    ) {
        process.terminate()
        if terminationObserver.wait(timeout: 0.5) == false, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            terminationObserver.finish()
        }
    }

    private static func terminateAsync(
        _ process: Process,
        terminationObserver: ProcessTerminationObserver
    ) async {
        process.terminate()
        if await terminationObserver.waitAsync(timeout: 0.5) == false, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            await waitUntilExitAsync(process, terminationObserver: terminationObserver)
        }
    }

    private static func waitUntilExitAsync(
        _ process: Process,
        terminationObserver: ProcessTerminationObserver
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                terminationObserver.finish()
                continuation.resume()
            }
        }
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }
}

private final class ProcessTerminationObserver: @unchecked Sendable {
    private let condition = NSCondition()
    private var isFinished = false
    private var callbacks: [@Sendable () -> Void] = []

    func finish() {
        let pendingCallbacks: [@Sendable () -> Void]
        condition.lock()
        guard isFinished == false else {
            condition.unlock()
            return
        }
        isFinished = true
        pendingCallbacks = callbacks
        callbacks = []
        condition.broadcast()
        condition.unlock()

        pendingCallbacks.forEach { $0() }
    }

    func wait(timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }

        while isFinished == false {
            guard timeout > 0 else {
                return false
            }
            if condition.wait(until: deadline) == false {
                return isFinished
            }
        }

        return true
    }

    func waitAsync(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let wait = ProcessAsyncWait(continuation: continuation)
            whenFinished {
                wait.resume(returning: true)
            }

            guard timeout > 0 else {
                wait.resume(returning: false)
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                wait.resume(returning: false)
            }
        }
    }

    private func whenFinished(_ callback: @escaping @Sendable () -> Void) {
        condition.lock()
        if isFinished {
            condition.unlock()
            callback()
        } else {
            callbacks.append(callback)
            condition.unlock()
        }
    }
}

private final class ProcessAsyncWait: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Bool, Never>

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Bool) {
        lock.lock()
        guard didResume == false else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        continuation.resume(returning: value)
    }
}
