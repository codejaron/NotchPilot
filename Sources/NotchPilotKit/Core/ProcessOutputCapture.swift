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
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

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

        if waitForExit(process, timeout: timeout) == false {
            process.terminate()
            if waitForExit(process, timeout: 0.5) == false, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }

        _ = drainGroup.wait(timeout: .now() + 1)
        return CapturedProcessOutput(
            terminationStatus: process.terminationStatus,
            standardOutput: outputBuffer.value,
            standardError: errorBuffer.value
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

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        return group.wait(timeout: .now() + timeout) == .success
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
