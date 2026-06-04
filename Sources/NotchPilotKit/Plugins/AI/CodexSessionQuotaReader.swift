import Foundation

protocol CodexSessionQuotaReading: Sendable {
    func latestSnapshot(collectedAt: Date, preferredFileURL: URL?) async -> AIUsageQuotaSnapshot?
}

extension CodexSessionQuotaReading {
    func latestSnapshot(collectedAt: Date) async -> AIUsageQuotaSnapshot? {
        await latestSnapshot(collectedAt: collectedAt, preferredFileURL: nil)
    }
}

actor CodexSessionQuotaReader: CodexSessionQuotaReading {
    private struct Candidate {
        let rawJSON: String
        let timestamp: Date
        let ordinal: Int
    }

    private struct CandidateCacheEntry {
        let modificationDate: Date
        let fileSize: UInt64
        let candidate: Candidate?
    }

    private let sessionsDirectoryURL: URL
    private let fileManager: FileManager
    private let maxFilesToScan: Int
    private let maxBytesPerFile: UInt64
    private let recentDayLimit: Int
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    private var candidateCacheByPath: [String: CandidateCacheEntry] = [:]

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        maxFilesToScan: Int = 48,
        maxBytesPerFile: UInt64 = 1_048_576,
        recentDayLimit: Int = 14,
        calendar: Calendar = Calendar(identifier: .gregorian),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sessionsDirectoryURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        self.fileManager = fileManager
        self.maxFilesToScan = maxFilesToScan
        self.maxBytesPerFile = maxBytesPerFile
        self.recentDayLimit = recentDayLimit
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func latestSnapshot(collectedAt: Date, preferredFileURL: URL?) async -> AIUsageQuotaSnapshot? {
        guard fileManager.fileExists(atPath: sessionsDirectoryURL.path) else {
            return nil
        }

        if let preferredFileURL,
           isSessionLogFile(preferredFileURL),
           let snapshot = snapshot(
               from: latestTokenCountCandidate(in: preferredFileURL),
               collectedAt: collectedAt
           ) {
            return snapshot
        }

        if let snapshot = snapshot(
            from: latestTokenCountCandidate(in: recentDatedSessionFiles()),
            collectedAt: collectedAt
        ) {
            return snapshot
        }

        return snapshot(
            from: latestTokenCountCandidate(in: legacyRecentSessionFiles()),
            collectedAt: collectedAt
        )
    }

    private func snapshot(from candidate: Candidate?, collectedAt: Date) -> AIUsageQuotaSnapshot? {
        candidate.flatMap {
            AIUsageQuotaSnapshot.codexSessionLog(rawJSON: $0.rawJSON, collectedAt: collectedAt)
        }
    }

    private func latestTokenCountCandidate(in urls: [URL]) -> Candidate? {
        urls
            .compactMap(latestTokenCountCandidate(in:))
            .max { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.ordinal < rhs.ordinal
            }
    }

    private func latestTokenCountCandidate(in url: URL) -> Candidate? {
        let cacheKey = url.standardizedFileURL.path
        let attributes = fileAttributes(for: url)
        if let attributes,
           let entry = candidateCacheByPath[cacheKey],
           entry.modificationDate == attributes.modificationDate,
           entry.fileSize == attributes.fileSize {
            return entry.candidate
        }

        let candidate = parseLatestTokenCountCandidate(in: url)
        if let attributes {
            candidateCacheByPath[cacheKey] = CandidateCacheEntry(
                modificationDate: attributes.modificationDate,
                fileSize: attributes.fileSize,
                candidate: candidate
            )
        }
        return candidate
    }

    private func parseLatestTokenCountCandidate(in url: URL) -> Candidate? {
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

    private func recentDatedSessionFiles() -> [URL] {
        let urls = recentSessionDateDirectories().flatMap { directoryURL -> [URL] in
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                return []
            }

            return ((try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? [])
            .filter(isSessionLogFile)
        }

        return sortedByModificationDate(urls)
    }

    private func legacyRecentSessionFiles() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let urls = enumerator
            .compactMap { $0 as? URL }
            .filter(isSessionLogFile)

        return sortedByModificationDate(Array(urls))
    }

    private func sortedByModificationDate(_ urls: [URL]) -> [URL] {
        urls
            .sorted { lhs, rhs in
                modificationDate(for: lhs) > modificationDate(for: rhs)
            }
            .prefix(maxFilesToScan)
            .map { $0 }
    }

    private func recentSessionDateDirectories() -> [URL] {
        let now = nowProvider()
        return (0..<recentDayLimit).compactMap { offset -> URL? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else {
                return nil
            }

            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day else {
                return nil
            }

            return sessionsDirectoryURL
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
        }
    }

    private func isSessionLogFile(_ url: URL) -> Bool {
        let standardizedSessionsPath = sessionsDirectoryURL.standardizedFileURL.path
        let standardizedPath = url.standardizedFileURL.path
        return url.pathExtension == "jsonl"
            && standardizedPath.hasPrefix(standardizedSessionsPath + "/")
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

    private func fileAttributes(for url: URL) -> (modificationDate: Date, fileSize: UInt64)? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date,
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            return nil
        }

        return (modificationDate, fileSize)
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
