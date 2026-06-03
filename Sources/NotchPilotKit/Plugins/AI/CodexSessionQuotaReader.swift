import Foundation

protocol CodexSessionQuotaReading {
    func latestSnapshot(collectedAt: Date) -> AIUsageQuotaSnapshot?
}

struct CodexSessionQuotaReader: CodexSessionQuotaReading {
    private struct Candidate {
        let rawJSON: String
        let timestamp: Date
        let ordinal: Int
    }

    private let sessionsDirectoryURL: URL
    private let fileManager: FileManager
    private let maxFilesToScan: Int
    private let maxBytesPerFile: UInt64

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        maxFilesToScan: Int = 48,
        maxBytesPerFile: UInt64 = 1_048_576
    ) {
        self.sessionsDirectoryURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        self.fileManager = fileManager
        self.maxFilesToScan = maxFilesToScan
        self.maxBytesPerFile = maxBytesPerFile
    }

    func latestSnapshot(collectedAt: Date) -> AIUsageQuotaSnapshot? {
        guard fileManager.fileExists(atPath: sessionsDirectoryURL.path) else {
            return nil
        }

        return latestTokenCountCandidate()
            .flatMap { AIUsageQuotaSnapshot.codexSessionLog(rawJSON: $0.rawJSON, collectedAt: collectedAt) }
    }

    private func latestTokenCountCandidate() -> Candidate? {
        recentSessionFiles()
            .compactMap(latestTokenCountCandidate(in:))
            .max { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.ordinal < rhs.ordinal
            }
    }

    private func recentSessionFiles() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { lhs, rhs in
                modificationDate(for: lhs) > modificationDate(for: rhs)
            }
            .prefix(maxFilesToScan)
            .map { $0 }
    }

    private func latestTokenCountCandidate(in url: URL) -> Candidate? {
        guard let content = tailContent(in: url) else {
            return nil
        }

        let fallbackTimestamp = modificationDate(for: url)
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .enumerated()
            .compactMap { offset, line -> Candidate? in
                let rawJSON = String(line)
                guard AIUsageQuotaSnapshot.isCodexTokenCount(rawJSON: rawJSON) else {
                    return nil
                }

                return Candidate(
                    rawJSON: rawJSON,
                    timestamp: AIUsageQuotaSnapshot.codexTokenCountTimestamp(rawJSON: rawJSON) ?? fallbackTimestamp,
                    ordinal: offset
                )
            }
            .max { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.ordinal < rhs.ordinal
            }
    }

    private func tailContent(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else {
            return nil
        }
        let offset = size > maxBytesPerFile ? size - maxBytesPerFile : 0
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }

        var content = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)

        if offset > 0,
           let newlineIndex = content.firstIndex(of: "\n") {
            content = String(content[content.index(after: newlineIndex)...])
        }
        return content
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
