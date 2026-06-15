import Foundation

public struct ScratchpadAttachment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var fileName: String
    public var relativePath: String
    public var originalURLString: String?
    public var byteCount: Int64?
    public var createdAt: Date
}

public struct ScratchpadNoteRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date?
    public var attachments: [ScratchpadAttachment]
    public var isTitleManuallySet: Bool
}

public struct ScratchpadNote: Equatable, Identifiable, Sendable {
    public static let untitledTitle = "Untitled"

    public var id: String
    public var title: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date?
    public var attachments: [ScratchpadAttachment]
    public var isTitleManuallySet: Bool

    static func derivedTitle(from body: String) -> String {
        let firstLine = body.components(separatedBy: .newlines).first ?? ""
        let strippedHeading = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^#{1,6}\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard strippedHeading.isEmpty == false else {
            return untitledTitle
        }

        if strippedHeading.count <= 80 {
            return strippedHeading
        }

        return String(strippedHeading.prefix(80))
    }
}

public struct ScratchpadIndex: Codable, Equatable, Sendable {
    public var notes: [ScratchpadNoteRecord]
    public var lastOpenedNoteID: String?

    public static let empty = ScratchpadIndex(notes: [], lastOpenedNoteID: nil)
}

public struct ScratchpadAttachmentMigrationResult: Equatable, Sendable {
    public var migratedCount: Int
    public var failedCount: Int
}

public enum ScratchpadStoreError: Error, Equatable {
    case noteNotFound(String)
    case attachmentSourceMissing(String)
}

public final class ScratchpadStore {
    public let rootURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        rootURL: URL? = nil,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL ?? homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("NotchPilot", isDirectory: true)
            .appendingPathComponent("Scratchpad", isDirectory: true)
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    public func loadIndex() throws -> ScratchpadIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: indexURL)
        return try decoder.decode(ScratchpadIndex.self, from: data)
    }

    @discardableResult
    public func createNote(now: Date = Date()) throws -> ScratchpadNote {
        try ensureRootDirectory()
        let noteID = UUID().uuidString
        let noteDirectory = directoryURL(forNoteID: noteID)
        try fileManager.createDirectory(
            at: noteDirectory.appendingPathComponent("attachments", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: noteFileURL(forNoteID: noteID), options: .atomic)

        var index = try loadIndex()
        let record = ScratchpadNoteRecord(
            id: noteID,
            title: ScratchpadNote.untitledTitle,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
            attachments: [],
            isTitleManuallySet: false
        )
        index.notes.insert(record, at: 0)
        index.lastOpenedNoteID = noteID
        try saveIndex(index)

        return ScratchpadNote(record: record, body: "")
    }

    public func loadNote(id noteID: String) throws -> ScratchpadNote? {
        let index = try loadIndex()
        guard let record = index.notes.first(where: { $0.id == noteID }) else {
            return nil
        }

        let body: String
        let noteURL = noteFileURL(forNoteID: noteID)
        if fileManager.fileExists(atPath: noteURL.path) {
            body = try String(contentsOf: noteURL)
        } else {
            body = ""
        }

        return ScratchpadNote(record: record, body: body)
    }

    @discardableResult
    public func saveNote(_ note: ScratchpadNote, now: Date = Date()) throws -> ScratchpadNote {
        var index = try loadIndex()
        guard let recordIndex = index.notes.firstIndex(where: { $0.id == note.id }) else {
            throw ScratchpadStoreError.noteNotFound(note.id)
        }

        try ensureNoteDirectory(note.id)
        try Data(note.body.utf8).write(to: noteFileURL(forNoteID: note.id), options: .atomic)

        var record = index.notes[recordIndex]
        record.title = record.isTitleManuallySet ? record.title : ScratchpadNote.derivedTitle(from: note.body)
        record.updatedAt = now
        index.notes[recordIndex] = record
        sortNotesInIndex(&index)
        try saveIndex(index)

        return ScratchpadNote(record: record, body: note.body)
    }

    @discardableResult
    public func renameNote(noteID: String, title: String, now: Date = Date()) throws -> ScratchpadNote {
        var index = try loadIndex()
        guard let recordIndex = index.notes.firstIndex(where: { $0.id == noteID }) else {
            throw ScratchpadStoreError.noteNotFound(noteID)
        }

        var record = index.notes[recordIndex]
        record.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ScratchpadNote.untitledTitle
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = now
        record.isTitleManuallySet = true
        index.notes[recordIndex] = record
        sortNotesInIndex(&index)
        try saveIndex(index)

        let body = try String(contentsOf: noteFileURL(forNoteID: noteID))
        return ScratchpadNote(record: record, body: body)
    }

    public func markOpened(noteID: String, now: Date = Date()) throws {
        var index = try loadIndex()
        guard let recordIndex = index.notes.firstIndex(where: { $0.id == noteID }) else {
            throw ScratchpadStoreError.noteNotFound(noteID)
        }

        index.notes[recordIndex].lastOpenedAt = now
        index.lastOpenedNoteID = noteID
        try saveIndex(index)
    }

    @discardableResult
    public func discardIfPristine(noteID: String) throws -> Bool {
        guard let note = try loadNote(id: noteID) else {
            return false
        }

        guard note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              note.isTitleManuallySet == false,
              note.attachments.isEmpty
        else {
            return false
        }

        try deleteNote(noteID: noteID)
        return true
    }

    public func deleteNote(noteID: String) throws {
        var index = try loadIndex()
        index.notes.removeAll { $0.id == noteID }
        if index.lastOpenedNoteID == noteID {
            index.lastOpenedNoteID = index.notes.max(by: { $0.updatedAt < $1.updatedAt })?.id
        }
        let noteDirectory = directoryURL(forNoteID: noteID)
        if fileManager.fileExists(atPath: noteDirectory.path) {
            try fileManager.removeItem(at: noteDirectory)
        }
        try saveIndex(index)
    }

    @discardableResult
    public func copyAttachment(
        from sourceURL: URL,
        toNoteID noteID: String,
        now: Date = Date()
    ) throws -> ScratchpadAttachment {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ScratchpadStoreError.attachmentSourceMissing(sourceURL.path)
        }

        try ensureNoteDirectory(noteID)
        let attachmentsDirectory = attachmentsDirectoryURL(forNoteID: noteID)
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        let destinationFileName = uniqueAttachmentFileName(
            preferredFileName: sourceURL.lastPathComponent,
            in: attachmentsDirectory
        )
        let destinationURL = attachmentsDirectory.appendingPathComponent(destinationFileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let byteCount = try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber
        let attachment = ScratchpadAttachment(
            id: UUID().uuidString,
            fileName: destinationFileName,
            relativePath: "attachments/\(destinationFileName)",
            originalURLString: sourceURL.path,
            byteCount: byteCount?.int64Value,
            createdAt: now
        )

        var index = try loadIndex()
        guard let recordIndex = index.notes.firstIndex(where: { $0.id == noteID }) else {
            throw ScratchpadStoreError.noteNotFound(noteID)
        }
        index.notes[recordIndex].attachments.append(attachment)
        index.notes[recordIndex].updatedAt = now
        try saveIndex(index)

        return attachment
    }

    @discardableResult
    public func writeAttachment(
        data: Data,
        preferredFileName: String,
        toNoteID noteID: String,
        originalURLString: String? = nil,
        now: Date = Date()
    ) throws -> ScratchpadAttachment {
        try ensureNoteDirectory(noteID)
        let attachmentsDirectory = attachmentsDirectoryURL(forNoteID: noteID)
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        let destinationFileName = uniqueAttachmentFileName(
            preferredFileName: preferredFileName,
            in: attachmentsDirectory
        )
        let destinationURL = attachmentsDirectory.appendingPathComponent(destinationFileName)
        try data.write(to: destinationURL, options: .atomic)

        let attachment = ScratchpadAttachment(
            id: UUID().uuidString,
            fileName: destinationFileName,
            relativePath: "attachments/\(destinationFileName)",
            originalURLString: originalURLString,
            byteCount: Int64(data.count),
            createdAt: now
        )

        var index = try loadIndex()
        guard let recordIndex = index.notes.firstIndex(where: { $0.id == noteID }) else {
            throw ScratchpadStoreError.noteNotFound(noteID)
        }
        index.notes[recordIndex].attachments.append(attachment)
        index.notes[recordIndex].updatedAt = now
        try saveIndex(index)

        return attachment
    }

    public func noteDirectoryURL(forNoteID noteID: String) -> URL {
        directoryURL(forNoteID: noteID)
    }

    public static func externalMarkdownFileURLs(in body: String) -> [URL] {
        guard let regex = try? markdownAbsoluteFileLinkRegex() else {
            return []
        }
        let nsBody = body as NSString
        return regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length)).compactMap { match in
            guard match.numberOfRanges == 4 else {
                return nil
            }
            let linkPath = nsBody.substring(with: match.range(at: 2))
            return URL(fileURLWithPath: linkPath)
        }
    }

    public static func missingExternalMarkdownFileURLs(
        in body: String,
        fileManager: FileManager = .default
    ) -> [URL] {
        externalMarkdownFileURLs(in: body).filter { url in
            fileManager.fileExists(atPath: url.path) == false
        }
    }

    @discardableResult
    public func migrateExternalMarkdownLinks(now: Date = Date()) throws -> ScratchpadAttachmentMigrationResult {
        var migratedCount = 0
        var failedCount = 0
        let index = try loadIndex()

        for record in index.notes {
            guard var note = try loadNote(id: record.id) else {
                continue
            }

            let migration = try migrateMarkdownLinks(in: note.body, noteID: record.id, now: now)
            migratedCount += migration.migratedCount
            failedCount += migration.failedCount
            if migration.body != note.body {
                note = try loadNote(id: record.id) ?? note
                note.body = migration.body
                _ = try saveNote(note, now: now)
            }
        }

        return ScratchpadAttachmentMigrationResult(
            migratedCount: migratedCount,
            failedCount: failedCount
        )
    }

    private func migrateMarkdownLinks(
        in body: String,
        noteID: String,
        now: Date
    ) throws -> (body: String, migratedCount: Int, failedCount: Int) {
        let regex = try Self.markdownAbsoluteFileLinkRegex()
        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        var migratedCount = 0
        var failedCount = 0
        var replacements: [(range: NSRange, value: String)] = []

        for match in matches {
            guard match.numberOfRanges == 4 else {
                continue
            }
            let linkPath = nsBody.substring(with: match.range(at: 2))
            guard linkPath.hasPrefix(rootURL.path) == false else {
                continue
            }

            let sourceURL = URL(fileURLWithPath: linkPath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                failedCount += 1
                continue
            }

            let attachment = try copyAttachment(from: sourceURL, toNoteID: noteID, now: now)
            replacements.append((match.range(at: 2), attachment.relativePath))
            migratedCount += 1
        }

        guard replacements.isEmpty == false else {
            return (body, migratedCount, failedCount)
        }

        let mutableBody = NSMutableString(string: body)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutableBody.replaceCharacters(in: replacement.range, with: replacement.value)
        }

        return (mutableBody as String, migratedCount, failedCount)
    }

    private static func markdownAbsoluteFileLinkRegex() throws -> NSRegularExpression {
        try NSRegularExpression(pattern: #"(!?\[[^\]]*\]\()(/[^\)]+)(\))"#)
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent("notes", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func ensureNoteDirectory(_ noteID: String) throws {
        try ensureRootDirectory()
        try fileManager.createDirectory(
            at: directoryURL(forNoteID: noteID).appendingPathComponent("attachments", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func saveIndex(_ index: ScratchpadIndex) throws {
        try ensureRootDirectory()
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private func sortNotesInIndex(_ index: inout ScratchpadIndex) {
        index.notes.sort { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func uniqueAttachmentFileName(preferredFileName: String, in directory: URL) -> String {
        let fallbackName = preferredFileName.isEmpty ? "Attachment" : preferredFileName
        let baseName = (fallbackName as NSString).deletingPathExtension
        let pathExtension = (fallbackName as NSString).pathExtension

        func candidateName(forSuffix suffix: Int?) -> String {
            let stem = suffix.map { "\(baseName) \($0)" } ?? baseName
            return pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)"
        }

        var candidate = candidateName(forSuffix: nil)
        var suffix = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = candidateName(forSuffix: suffix)
            suffix += 1
        }
        return candidate
    }

    private func directoryURL(forNoteID noteID: String) -> URL {
        rootURL
            .appendingPathComponent("notes", isDirectory: true)
            .appendingPathComponent(noteID, isDirectory: true)
    }

    private func noteFileURL(forNoteID noteID: String) -> URL {
        directoryURL(forNoteID: noteID).appendingPathComponent("note.md")
    }

    private func attachmentsDirectoryURL(forNoteID noteID: String) -> URL {
        directoryURL(forNoteID: noteID).appendingPathComponent("attachments", isDirectory: true)
    }
}

private extension ScratchpadNote {
    init(record: ScratchpadNoteRecord, body: String) {
        self.id = record.id
        self.title = record.title
        self.body = body
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.lastOpenedAt = record.lastOpenedAt
        self.attachments = record.attachments
        self.isTitleManuallySet = record.isTitleManuallySet
    }
}
