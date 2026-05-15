import Foundation

/// Reads Claude Code session transcript JSONL files (the `transcript_path`
/// pointed to by every hook event) to extract real token usage. Hook payloads
/// themselves never carry `usage`; the JSONL is the authoritative source that
/// `/context` and `/cost` read from.
///
/// Usage semantics mirror Claude Code's own indicators:
///   * `contextInputTokens` — the most recent assistant message's
///     `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.
///     Each turn re-sends the whole conversation, so this number is the
///     current context-window occupancy.
///   * `totalOutputTokens` — sum of `output_tokens` across every assistant
///     message in the file (cumulative work generated this session).
public protocol ClaudeTranscriptReading: Sendable {
    func usage(forSessionID sessionID: String, transcriptPath: String) async -> ClaudeTranscriptUsage?
    func reset() async
}

public struct ClaudeTranscriptUsage: Equatable, Sendable {
    public let contextInputTokens: Int
    public let totalOutputTokens: Int
}

public actor ClaudeTranscriptReader: ClaudeTranscriptReading {
    private struct CacheEntry {
        let path: String
        let modificationDate: Date
        let size: UInt64
        let usage: ClaudeTranscriptUsage
    }

    private var cache: [String: CacheEntry] = [:]

    public init() {}

    public func usage(forSessionID sessionID: String, transcriptPath: String) -> ClaudeTranscriptUsage? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: transcriptPath)
        let modDate = attrs?[.modificationDate] as? Date
        let size = (attrs?[.size] as? NSNumber)?.uint64Value

        if let modDate, let size, let entry = cache[sessionID],
           entry.path == transcriptPath,
           entry.modificationDate == modDate,
           entry.size == size {
            return entry.usage
        }

        guard let usage = parseUsage(atPath: transcriptPath) else {
            return cache[sessionID]?.usage
        }

        if let modDate, let size {
            cache[sessionID] = CacheEntry(
                path: transcriptPath,
                modificationDate: modDate,
                size: size,
                usage: usage
            )
        }
        return usage
    }

    public func reset() {
        cache.removeAll()
    }

    private func parseUsage(atPath path: String) -> ClaudeTranscriptUsage? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        var latestContextInput: Int?
        var totalOutput = 0
        var sawAny = false

        text.enumerateLines { line, _ in
            guard line.contains("\"usage\"") else { return }
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (object["type"] as? String) == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else {
                return
            }

            sawAny = true

            let input = ClaudeTranscriptReader.intValue(usage["input_tokens"]) ?? 0
            let cacheCreate = ClaudeTranscriptReader.intValue(usage["cache_creation_input_tokens"]) ?? 0
            let cacheRead = ClaudeTranscriptReader.intValue(usage["cache_read_input_tokens"]) ?? 0
            let output = ClaudeTranscriptReader.intValue(usage["output_tokens"]) ?? 0

            latestContextInput = input + cacheCreate + cacheRead
            totalOutput += output
        }

        guard sawAny else { return nil }

        return ClaudeTranscriptUsage(
            contextInputTokens: latestContextInput ?? 0,
            totalOutputTokens: totalOutput
        )
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let int = raw as? Int { return int }
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String { return Int(string) }
        return nil
    }
}
