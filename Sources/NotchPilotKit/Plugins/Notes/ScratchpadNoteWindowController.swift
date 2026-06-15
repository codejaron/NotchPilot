import AppKit
import SwiftUI

@MainActor
final class ScratchpadNoteWindowController: NSObject, NSWindowDelegate {
    private var windowsByNoteID: [String: NSWindow] = [:]
    private var viewModelsByNoteID: [String: ScratchpadNotesViewModel] = [:]

    var openWindowCount: Int {
        windowsByNoteID.count
    }

    @discardableResult
    func show(noteID: String, store: ScratchpadStore) throws -> NSWindow {
        if let existing = windowsByNoteID[noteID] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return existing
        }

        guard try store.loadNote(id: noteID) != nil else {
            throw ScratchpadStoreError.noteNotFound(noteID)
        }

        let viewModel = ScratchpadNotesViewModel(store: store)
        try viewModel.load()
        try viewModel.selectNote(id: noteID, discardsCurrentPristine: false)
        viewModelsByNoteID[noteID] = viewModel

        let windowBox = ScratchpadNoteWindowBox()
        let rootView = ScratchpadStandaloneNoteWindowView(
            viewModel: viewModel,
            onTogglePinned: { isPinned in
                windowBox.window?.level = isPinned ? .floating : .normal
            },
            onDelete: { [weak self] noteID in
                do {
                    try viewModel.deleteNote(id: noteID)
                    windowBox.window?.close()
                    self?.windowsByNoteID.removeValue(forKey: noteID)
                    self?.viewModelsByNoteID.removeValue(forKey: noteID)
                } catch {
                    NSLog("NotchPilot failed to delete scratchpad note window note: \(error.localizedDescription)")
                }
            }
        )
        let created = Self.makeWindow(rootView: rootView, title: viewModel.selectedNote?.title ?? "Notes")
        created.delegate = self
        created.isReleasedWhenClosed = false
        windowsByNoteID[noteID] = created
        windowBox.window = created
        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return created
    }

    func viewModel(noteID: String) -> ScratchpadNotesViewModel? {
        viewModelsByNoteID[noteID]
    }

    func flushPendingSaves() {
        for viewModel in viewModelsByNoteID.values {
            do {
                try viewModel.flushPendingSave()
            } catch {
                NSLog("NotchPilot failed to flush scratchpad note window: \(error.localizedDescription)")
            }
        }
    }

    static func makeWindow<Content: View>(rootView: Content, title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 460, height: 320)
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: rootView)
        return window
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else {
            return
        }

        Task { @MainActor [weak self, weak closingWindow] in
            guard let self, let closingWindow else { return }
            if let noteID = self.windowsByNoteID.first(where: { $0.value === closingWindow })?.key {
                try? self.viewModelsByNoteID[noteID]?.flushPendingSave()
                self.windowsByNoteID.removeValue(forKey: noteID)
                self.viewModelsByNoteID.removeValue(forKey: noteID)
            }
        }
    }
}

private final class ScratchpadNoteWindowBox {
    weak var window: NSWindow?
}

private struct ScratchpadStandaloneNoteWindowView: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject var viewModel: ScratchpadNotesViewModel

    @State private var text = ""
    @State private var isPinned = false
    @State private var errorMessage: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var isRenameAlertPresented = false
    @State private var renameText = ""

    let onTogglePinned: (Bool) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            ScratchpadMarkdownEditor(
                text: $text,
                onTextChange: { newText in
                    perform { try viewModel.updateSelectedBody(newText) }
                },
                onDroppedFiles: { urls in
                    perform {
                        for url in urls {
                            try viewModel.insertAttachment(
                                from: url,
                                isImage: ScratchpadNoteWindowFileKind.isImage(url)
                            )
                        }
                        syncText()
                    }
                },
                onPastedImages: { images in
                    perform {
                        for image in images {
                            try viewModel.insertPastedImage(image)
                        }
                        syncText()
                    }
                }
            )
            .background(Color.black)

            if missingExternalFileCount > 0 {
                Label(
                    AppStrings.missingExternalFiles(count: missingExternalFileCount, language: language),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchPilotTheme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchPilotTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .onAppear {
            syncText()
        }
        .onDisappear {
            perform {
                try viewModel.discardSelectedIfPristine()
            }
        }
        .onChange(of: viewModel.selectedNote?.id) { _, _ in
            syncText()
        }
        .confirmationDialog(AppStrings.text(.deleteNoteQuestion, language: language), isPresented: $isDeleteConfirmationPresented) {
            Button(AppStrings.text(.deleteNote, language: language), role: .destructive) {
                if let noteID = viewModel.selectedNote?.id {
                    onDelete(noteID)
                }
            }
            Button(AppStrings.text(.cancel, language: language), role: .cancel) {}
        }
        .alert(AppStrings.text(.renameNote, language: language), isPresented: $isRenameAlertPresented) {
            TextField(AppStrings.text(.noteTitle, language: language), text: $renameText)
            Button(AppStrings.text(.renameNote, language: language)) {
                perform {
                    try viewModel.renameSelectedNote(renameText)
                    syncText()
                }
            }
            Button(AppStrings.text(.cancel, language: language), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                beginRename()
            } label: {
                Text(viewModel.selectedNote?.title ?? ScratchpadNote.untitledTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isPinned.toggle()
                onTogglePinned(isPinned)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(AppStrings.text(.keepOnTop, language: language))

            Menu {
                Button(AppStrings.text(.renameNote, language: language), action: beginRename)
                Button(AppStrings.text(.openNoteFolder, language: language), action: revealNoteFolder)
                Button(AppStrings.text(.deleteNote, language: language), role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.white)
        }
    }

    private func beginRename() {
        renameText = viewModel.selectedNote?.title ?? ""
        isRenameAlertPresented = true
    }

    private func revealNoteFolder() {
        guard let note = viewModel.selectedNote else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            viewModel.noteDirectoryURL(for: note.id),
        ])
    }

    private func syncText() {
        text = viewModel.selectedNote?.body ?? ""
    }

    private var missingExternalFileCount: Int {
        ScratchpadStore.missingExternalMarkdownFileURLs(in: viewModel.selectedNote?.body ?? "").count
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

private enum ScratchpadNoteWindowFileKind {
    static func isImage(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp":
            return true
        default:
            return false
        }
    }
}
