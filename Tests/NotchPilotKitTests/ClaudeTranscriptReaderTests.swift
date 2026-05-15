import XCTest
@testable import NotchPilotKit

final class ClaudeTranscriptReaderTests: XCTestCase {
    func testParsesLatestContextInputAndCumulativeOutput() async throws {
        let url = try writeTranscript("""
        {"type":"user","message":{"role":"user","content":"hi"}}
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":200,"output_tokens":40}}}
        {"type":"user","message":{"role":"user","content":"more"}}
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":110,"cache_creation_input_tokens":0,"cache_read_input_tokens":380,"output_tokens":75}}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = ClaudeTranscriptReader()
        let usage = await reader.usage(forSessionID: "s1", transcriptPath: url.path)

        XCTAssertEqual(usage?.contextInputTokens, 110 + 0 + 380)
        XCTAssertEqual(usage?.totalOutputTokens, 40 + 75)
    }

    func testIgnoresUserAndSystemEntries() async throws {
        let url = try writeTranscript("""
        {"type":"user","message":{"role":"user","usage":{"input_tokens":9999,"output_tokens":9999}}}
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = ClaudeTranscriptReader()
        let usage = await reader.usage(forSessionID: "s2", transcriptPath: url.path)

        XCTAssertEqual(usage?.contextInputTokens, 10)
        XCTAssertEqual(usage?.totalOutputTokens, 5)
    }

    func testReturnsNilWhenTranscriptHasNoAssistantUsage() async throws {
        let url = try writeTranscript("""
        {"type":"user","message":{"role":"user","content":"hi"}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = ClaudeTranscriptReader()
        let usage = await reader.usage(forSessionID: "s3", transcriptPath: url.path)

        XCTAssertNil(usage)
    }

    func testReturnsCachedValueWhenFileUnchangedAndFreshValueWhenAppended() async throws {
        let url = try writeTranscript("""
        {"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = ClaudeTranscriptReader()
        let first = await reader.usage(forSessionID: "s4", transcriptPath: url.path)
        XCTAssertEqual(first?.totalOutputTokens, 5)

        // Force a perceptible mtime change before appending so the cache invalidates.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -10)],
            ofItemAtPath: url.path
        )

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"usage\":{\"input_tokens\":20,\"output_tokens\":7}}}\n".utf8))
        try handle.close()

        let second = await reader.usage(forSessionID: "s4", transcriptPath: url.path)
        XCTAssertEqual(second?.contextInputTokens, 20)
        XCTAssertEqual(second?.totalOutputTokens, 12)
    }

    private func writeTranscript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-transcript-\(UUID().uuidString).jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
