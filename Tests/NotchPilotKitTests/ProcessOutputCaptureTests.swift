import XCTest
@testable import NotchPilotKit

final class ProcessOutputCaptureTests: XCTestCase {
    func testRunCapturesStandardOutputLargerThanPipeBuffer() throws {
        let output = try XCTUnwrap(ProcessOutputCapture.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: ["-e", "print 'x' x 200000"],
            timeout: 2
        ))

        XCTAssertEqual(output.terminationStatus, 0)
        XCTAssertEqual(output.standardOutput.count, 200_000)
    }

    func testRunCompletesWhenStandardErrorExceedsPipeBuffer() throws {
        let output = try XCTUnwrap(ProcessOutputCapture.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: ["-e", "print STDERR 'e' x 200000; print 'ok'"],
            timeout: 2
        ))

        XCTAssertEqual(output.terminationStatus, 0)
        XCTAssertEqual(String(data: output.standardOutput, encoding: .utf8), "ok")
    }
}
