import AppKit
import SwiftUI

struct ScratchpadNotesRootView: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject var viewModel: ScratchpadNotesViewModel

    @State private var editorText = ""
    @State private var errorMessage: String?
    @State private var pendingDeleteNote: ScratchpadNote?

    init(viewModel: ScratchpadNotesViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.isShowingList {
                ScratchpadNotesListView(
                    viewModel: viewModel,
                    language: language,
                    onSelect: { note in
                        perform {
                            try viewModel.selectNote(id: note.id)
                            syncEditorText()
                        }
                    },
                    onDelete: { pendingDeleteNote = $0 }
                )
            } else {
                ScratchpadNoteDetailView(
                    note: viewModel.selectedNote,
                    text: $editorText,
                    language: language,
                    onTextChange: { newText in
                        perform { try viewModel.updateSelectedBody(newText) }
                    },
                    onDroppedFiles: insertDroppedFiles,
                    onPastedImages: insertPastedImages
                )
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchPilotTheme.danger)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            perform {
                try viewModel.load()
                syncEditorText()
            }
        }
        .onDisappear {
            perform {
                try viewModel.discardSelectedIfPristine()
            }
        }
        .onChange(of: viewModel.selectedNote?.id) { _, _ in
            syncEditorText()
        }
        .onChange(of: viewModel.selectedNote?.body) { _, _ in
            syncEditorText()
        }
        .confirmationDialog(
            AppStrings.text(.deleteNoteQuestion, language: language),
            isPresented: Binding(
                get: { pendingDeleteNote != nil },
                set: { if $0 == false { pendingDeleteNote = nil } }
            )
        ) {
            Button(AppStrings.text(.deleteNote, language: language), role: .destructive) {
                guard let note = pendingDeleteNote else { return }
                perform {
                    try viewModel.deleteNote(id: note.id)
                    syncEditorText()
                    pendingDeleteNote = nil
                }
            }
            Button(AppStrings.text(.cancel, language: language), role: .cancel) {
                pendingDeleteNote = nil
            }
        }
    }

    private func insertDroppedFiles(_ urls: [URL]) {
        perform {
            for url in urls {
                try viewModel.insertAttachment(
                    from: url,
                    isImage: ScratchpadNoteFileKind.isImage(url)
                )
            }
            syncEditorText()
        }
    }

    private func insertPastedImages(_ images: [NSImage]) {
        perform {
            for image in images {
                try viewModel.insertPastedImage(image)
            }
            syncEditorText()
        }
    }

    private func syncEditorText() {
        editorText = viewModel.selectedNote?.body ?? ""
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }
}

private struct ScratchpadNotesListView: View {
    @ObservedObject var viewModel: ScratchpadNotesViewModel

    let language: AppLanguage
    let onSelect: (ScratchpadNote) -> Void
    let onDelete: (ScratchpadNote) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchPilotTheme.islandTextMuted)
                TextField(AppStrings.text(.searchNotes, language: language), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(0.08)))

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.filteredNotes) { note in
                        ScratchpadNoteRow(
                            note: note,
                            isSelected: note.id == viewModel.selectedNote?.id,
                            language: language,
                            onSelect: { onSelect(note) },
                            onDelete: { onDelete(note) }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

private struct ScratchpadNoteRow: View {
    let note: ScratchpadNote
    let isSelected: Bool
    let language: AppLanguage
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(note.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NotchPilotTheme.islandTextMuted)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Text(note.previewText(language: language))
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if note.fileReferenceCount > 0 {
                            Label("\(note.fileReferenceCount)", systemImage: "paperclip")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(NotchPilotTheme.islandTextMuted)
                        }

                        if note.missingExternalFileCount > 0 {
                            Label("\(note.missingExternalFileCount)", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(NotchPilotTheme.warning)
                                .help(AppStrings.text(.missingExternalFiles, language: language))
                        }
                    }
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchPilotTheme.islandTextMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? NotchPilotTheme.notes.opacity(0.16) : Color.white.opacity(0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? NotchPilotTheme.notes.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ScratchpadNoteDetailView: View {
    let note: ScratchpadNote?
    @Binding var text: String
    let language: AppLanguage

    let onTextChange: (String) -> Void
    let onDroppedFiles: ([URL]) -> Void
    let onPastedImages: ([NSImage]) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ScratchpadMarkdownEditor(
                text: $text,
                onTextChange: onTextChange,
                onDroppedFiles: onDroppedFiles,
                onPastedImages: onPastedImages
            )
            .background(Color.black.opacity(0.2))

            if missingExternalFileCount > 0 {
                Label(
                    AppStrings.missingExternalFiles(count: missingExternalFileCount, language: language),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchPilotTheme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var missingExternalFileCount: Int {
        note?.missingExternalFileCount ?? 0
    }
}

struct ScratchpadNotesHeaderAccessory: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject var viewModel: ScratchpadNotesViewModel

    let isOpenPinned: Bool
    let onTogglePin: () -> Void
    let onPopOut: (ScratchpadNote) -> Void

    @State private var isRenameAlertPresented = false
    @State private var renameText = ""
    @State private var pendingDeleteNote: ScratchpadNote?

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isShowingList == false {
                NotesIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: AppStrings.text(.allNotes, language: language)
                ) {
                    viewModel.isShowingList = true
                }
            }

            if viewModel.isShowingList {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button(action: beginRename) {
                    Text(headerTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            NotesIconButton(
                systemName: "plus",
                accessibilityLabel: AppStrings.text(.newNote, language: language),
                action: createNote
            )

            NotesIconButton(
                systemName: isOpenPinned ? "pin.fill" : "pin",
                accessibilityLabel: AppStrings.text(.pinNotch, language: language),
                isActive: isOpenPinned,
                action: onTogglePin
            )
            .scaleEffect(isOpenPinned ? 1.08 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isOpenPinned)

            NotesIconButton(
                systemName: "macwindow",
                accessibilityLabel: AppStrings.text(.popOutNote, language: language),
                action: popOutSelectedNote
            )

            Menu {
                Button(AppStrings.text(.renameNote, language: language), action: beginRename)
                    .disabled(viewModel.isShowingList)
                Button(AppStrings.text(.openNoteFolder, language: language), action: revealSelectedNote)
                    .disabled(viewModel.selectedNote == nil)
                Button(AppStrings.text(.deleteNote, language: language), role: .destructive) {
                    pendingDeleteNote = viewModel.selectedNote
                }
                .disabled(viewModel.selectedNote == nil)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
        }
        .frame(minWidth: 360, maxWidth: 620)
        .confirmationDialog(
            AppStrings.text(.deleteNoteQuestion, language: language),
            isPresented: Binding(
                get: { pendingDeleteNote != nil },
                set: { if $0 == false { pendingDeleteNote = nil } }
            )
        ) {
            Button(AppStrings.text(.deleteNote, language: language), role: .destructive) {
                guard let note = pendingDeleteNote else { return }
                do {
                    try viewModel.deleteNote(id: note.id)
                    pendingDeleteNote = nil
                } catch {
                    NSLog("NotchPilot failed to delete scratchpad note: \(error.localizedDescription)")
                }
            }
            Button(AppStrings.text(.cancel, language: language), role: .cancel) {
                pendingDeleteNote = nil
            }
        }
        .alert(AppStrings.text(.renameNote, language: language), isPresented: $isRenameAlertPresented) {
            TextField(AppStrings.text(.noteTitle, language: language), text: $renameText)
            Button(AppStrings.text(.renameNote, language: language)) {
                do {
                    try viewModel.renameSelectedNote(renameText)
                } catch {
                    NSLog("NotchPilot failed to rename scratchpad note: \(error.localizedDescription)")
                }
            }
            Button(AppStrings.text(.cancel, language: language), role: .cancel) {}
        }
    }

    private var headerTitle: String {
        viewModel.isShowingList
            ? AppStrings.text(.allNotes, language: language)
            : viewModel.selectedNote?.title ?? ScratchpadNote.untitledTitle
    }

    private func createNote() {
        do {
            try viewModel.discardSelectedIfPristine()
            _ = try viewModel.createNote()
        } catch {
            NSLog("NotchPilot failed to create scratchpad note: \(error.localizedDescription)")
        }
    }

    private func beginRename() {
        guard viewModel.isShowingList == false else {
            return
        }
        renameText = viewModel.selectedNote?.title ?? ""
        isRenameAlertPresented = true
    }

    private func popOutSelectedNote() {
        do {
            try viewModel.flushPendingSave()
            guard let note = viewModel.selectedNote else {
                return
            }
            viewModel.skipNextPristineDiscard()
            onPopOut(note)
        } catch {
            NSLog("NotchPilot failed to pop out scratchpad note: \(error.localizedDescription)")
        }
    }

    private func revealSelectedNote() {
        guard let note = viewModel.selectedNote else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            viewModel.noteDirectoryURL(for: note.id),
        ])
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }
}

private struct NotesIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotchPilotTheme.islandTextPrimary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                )
                .overlay {
                    Circle()
                        .strokeBorder(isActive ? Color.white.opacity(0.14) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private enum ScratchpadNoteFileKind {
    static func isImage(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp":
            return true
        default:
            return false
        }
    }
}

private extension ScratchpadNote {
    var fileReferenceCount: Int {
        attachments.count + ScratchpadStore.externalMarkdownFileURLs(in: body).count
    }

    var missingExternalFileCount: Int {
        ScratchpadStore.missingExternalMarkdownFileURLs(in: body).count
    }

    func previewText(language: AppLanguage) -> String {
        let flattened = body
            .components(separatedBy: .newlines)
            .dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if flattened.isEmpty == false {
            return flattened
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStrings.text(.noContent, language: language)
            : body
    }
}
