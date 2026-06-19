import AppKit
import Combine
import Foundation

@MainActor
final class ScratchpadNotesViewModel: ObservableObject {
    @Published private(set) var notes: [ScratchpadNote] = []
    @Published private(set) var selectedNote: ScratchpadNote?
    @Published var searchText = ""
    @Published var isShowingList = false

    let store: ScratchpadStore
    private let copyDraggedFilesToScratchpad: () -> Bool
    private let autosaveDelay: Duration
    private var pendingSave: PendingBodySave?
    private var pendingSaveTask: Task<Void, Never>?
    private var skipsNextPristineDiscard = false

    init(
        store: ScratchpadStore = ScratchpadStore(),
        autosaveDelay: Duration = .milliseconds(400),
        copyDraggedFilesToScratchpad: @escaping () -> Bool = {
            SettingsStore.shared.notes.notesCopyDraggedFilesToScratchpad
        }
    ) {
        self.store = store
        self.autosaveDelay = autosaveDelay
        self.copyDraggedFilesToScratchpad = copyDraggedFilesToScratchpad
    }

    deinit {
        pendingSaveTask?.cancel()
    }

    var filteredNotes: [ScratchpadNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return notes
        }

        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
        }
    }

    func load(now: Date = Date()) throws {
        try flushPendingSave()
        let index = try store.loadIndex()
        notes = try index.notes.compactMap { record in
            try store.loadNote(id: record.id)
        }

        if let lastOpenedNoteID = index.lastOpenedNoteID,
           let lastOpenedNote = notes.first(where: { $0.id == lastOpenedNoteID }) {
            try markLoadedNoteOpened(noteID: lastOpenedNote.id, now: now)
            return
        }

        if let first = notes.first {
            try markLoadedNoteOpened(noteID: first.id, now: now)
            return
        }

        selectedNote = try store.createNote(now: now)
        notes = [selectedNote].compactMap { $0 }
    }

    @discardableResult
    func createNote(now: Date = Date()) throws -> ScratchpadNote {
        try flushPendingSave()
        let note = try store.createNote(now: now)
        selectedNote = note
        isShowingList = false
        try refreshNotes()
        return note
    }

    func selectNote(
        id noteID: String,
        now: Date = Date(),
        discardsCurrentPristine: Bool = true
    ) throws {
        if selectedNote?.id == noteID || discardsCurrentPristine == false {
            try flushPendingSave()
        } else {
            try discardSelectedIfPristine()
        }
        try store.markOpened(noteID: noteID, now: now)
        try refreshNotes()
        selectedNote = try store.loadNote(id: noteID)
        isShowingList = false
    }

    func updateSelectedBody(_ body: String, now: Date = Date()) throws {
        guard var note = selectedNote else {
            return
        }

        note.body = body
        note.updatedAt = now
        if note.isTitleManuallySet == false {
            note.title = ScratchpadNote.derivedTitle(from: body)
        }
        selectedNote = note
        updateLocalNote(note)
        pendingSave = PendingBodySave(noteID: note.id, body: body, now: now)
        schedulePendingSave()
    }

    func renameSelectedNote(_ title: String, now: Date = Date()) throws {
        guard let noteID = selectedNote?.id else {
            return
        }

        try flushPendingSave()
        let renamed = try store.renameNote(noteID: noteID, title: title, now: now)
        selectedNote = renamed
        try refreshNotes()
    }

    func deleteNote(id noteID: String) throws {
        if pendingSave?.noteID == noteID {
            cancelPendingSave()
        } else {
            try flushPendingSave()
        }
        try store.deleteNote(noteID: noteID)
        try refreshNotes()
        if selectedNote?.id == noteID {
            selectedNote = notes.first
        }
    }

    func discardSelectedIfPristine() throws {
        if skipsNextPristineDiscard {
            skipsNextPristineDiscard = false
            return
        }

        guard let noteID = selectedNote?.id else {
            return
        }

        try flushPendingSave()
        let discarded = try store.discardIfPristine(noteID: noteID)
        if discarded {
            try refreshNotes()
            selectedNote = notes.first
        }
    }

    func insertAttachment(
        from sourceURL: URL,
        isImage: Bool,
        now: Date = Date()
    ) throws {
        guard selectedNote != nil else {
            _ = try createNote(now: now)
            return try insertAttachment(from: sourceURL, isImage: isImage, now: now)
        }

        let linkPath: String
        if copyDraggedFilesToScratchpad() {
            let attachment = try store.copyAttachment(from: sourceURL, toNoteID: selectedNote!.id, now: now)
            linkPath = attachment.relativePath
        } else {
            linkPath = sourceURL.path
        }

        let markdown = Self.markdownLink(
            fileName: sourceURL.lastPathComponent,
            path: linkPath,
            isImage: isImage
        )
        let separator = selectedNote?.body.isEmpty == false ? "\n" : ""
        try updateSelectedBody((selectedNote?.body ?? "") + separator + markdown, now: now)
    }

    @discardableResult
    func ensureDropTargetNote(now: Date = Date()) throws -> ScratchpadNote {
        try load(now: now)
        if let selectedNote {
            return selectedNote
        }

        return try createNote(now: now)
    }

    func insertPastedImage(_ image: NSImage, now: Date = Date()) throws {
        guard selectedNote != nil else {
            _ = try createNote(now: now)
            return try insertPastedImage(image, now: now)
        }

        guard let data = image.pngData else {
            return
        }

        let attachment = try store.writeAttachment(
            data: data,
            preferredFileName: "Pasted Image.png",
            toNoteID: selectedNote!.id,
            now: now
        )
        let markdown = Self.markdownLink(
            fileName: attachment.fileName,
            path: attachment.relativePath,
            isImage: true
        )
        let separator = selectedNote?.body.isEmpty == false ? "\n" : ""
        try updateSelectedBody((selectedNote?.body ?? "") + separator + markdown, now: now)
    }

    func flushPendingSave() throws {
        cancelPendingSaveTask()
        try savePendingBody()
    }

    func skipNextPristineDiscard() {
        skipsNextPristineDiscard = true
    }

    func noteDirectoryURL(for noteID: String) -> URL {
        store.noteDirectoryURL(forNoteID: noteID)
    }

    static func markdownLink(fileName: String, path: String, isImage: Bool) -> String {
        if isImage {
            return "![\(fileName)](\(path))"
        }
        return "[\(fileName)](\(path))"
    }

    static func isImageAttachment(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp":
            return true
        default:
            return false
        }
    }

    private func refreshNotes() throws {
        let index = try store.loadIndex()
        notes = try index.notes.compactMap { record in
            try store.loadNote(id: record.id)
        }
        if let selectedID = selectedNote?.id {
            selectedNote = notes.first(where: { $0.id == selectedID }) ?? selectedNote
        }
    }

    private func markLoadedNoteOpened(noteID: String, now: Date) throws {
        try store.markOpened(noteID: noteID, now: now)
        try refreshNotes()
        selectedNote = try store.loadNote(id: noteID)
    }

    private func updateLocalNote(_ note: ScratchpadNote) {
        if let noteIndex = notes.firstIndex(where: { $0.id == note.id }) {
            notes[noteIndex] = note
        } else {
            notes.insert(note, at: 0)
        }
        notes.sort { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func schedulePendingSave() {
        cancelPendingSaveTask()
        let delay = autosaveDelay
        pendingSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            await MainActor.run { [weak self] in
                self?.autosavePendingBody()
            }
        }
    }

    private func autosavePendingBody() {
        pendingSaveTask = nil
        do {
            try savePendingBody()
        } catch {
            NSLog("NotchPilot failed to autosave scratchpad note: \(error.localizedDescription)")
        }
    }

    private func savePendingBody() throws {
        guard let pendingSave else {
            return
        }

        guard var note = try store.loadNote(id: pendingSave.noteID) else {
            throw ScratchpadStoreError.noteNotFound(pendingSave.noteID)
        }
        note.body = pendingSave.body
        let saved = try store.saveNote(note, now: pendingSave.now)
        if selectedNote?.id == saved.id {
            selectedNote = saved
        }
        try refreshNotes()
        self.pendingSave = nil
    }

    private func cancelPendingSave() {
        cancelPendingSaveTask()
        pendingSave = nil
    }

    private func cancelPendingSaveTask() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
    }

    private struct PendingBodySave {
        var noteID: String
        var body: String
        var now: Date
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
