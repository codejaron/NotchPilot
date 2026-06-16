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
            NotchPilotWindowForegroundPresenter.present(existing)
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
                Self.applyPinnedState(isPinned, to: windowBox.window)
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
        NotchPilotWindowForegroundPresenter.present(created)
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

    static let defaultWindowSize = NSSize(width: 620, height: 460)

    static func defaultWindowFrame(in visibleFrame: NSRect?) -> NSRect {
        let size = defaultWindowSize
        guard let visibleFrame, visibleFrame.isEmpty == false else {
            return NSRect(origin: .zero, size: size)
        }

        return NSRect(
            x: visibleFrame.minX + max(0, (visibleFrame.width - size.width) / 2),
            y: visibleFrame.minY + max(0, (visibleFrame.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
    }

    static func makeWindow<Content: View>(rootView: Content, title: String) -> NSWindow {
        let window = ScratchpadNoteWindowPanel(
            contentRect: defaultWindowFrame(in: NSScreen.main?.visibleFrame),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 460, height: 320)
        window.isOpaque = false
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.backgroundColor = NSColor(
            calibratedRed: 0.045,
            green: 0.048,
            blue: 0.06,
            alpha: 0.96
        )
        window.contentView = ScratchpadNoteWindowHostingView(
            rootView: rootView.ignoresSafeArea(.container, edges: .top)
        )
        applyPinnedState(false, to: window)
        return window
    }

    static func applyPinnedState(_ isPinned: Bool, to window: NSWindow?) {
        guard let window else {
            return
        }

        let pinnedBehaviors: NSWindow.CollectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient,
        ]
        let unpinnedBehaviors: NSWindow.CollectionBehavior = [
            .managed,
            .participatesInCycle,
        ]

        if isPinned {
            (window as? NSPanel)?.isFloatingPanel = true
            window.collectionBehavior.remove(unpinnedBehaviors.union(.stationary))
            window.collectionBehavior.insert(pinnedBehaviors)
            window.level = .screenSaver
            window.orderFrontRegardless()
        } else {
            (window as? NSPanel)?.isFloatingPanel = false
            window.collectionBehavior.remove(pinnedBehaviors)
            window.collectionBehavior.remove(.stationary)
            window.collectionBehavior.insert(unpinnedBehaviors)
            window.level = .normal
        }
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

protocol ScratchpadNoteWindowFullscreenPanel: AnyObject {}

private final class ScratchpadNoteWindowPanel: NSPanel, ScratchpadNoteWindowFullscreenPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

protocol ScratchpadNoteWindowFullSizeContentHosting: AnyObject {}

private final class ScratchpadNoteWindowHostingView<Content: View>: NSHostingView<Content>,
    ScratchpadNoteWindowFullSizeContentHosting
{
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

private final class ScratchpadNoteWindowBox {
    weak var window: NSWindow?
}

enum ScratchpadStandaloneWindowChromeMetrics {
    static let titleBarHeight: CGFloat = 32
    static let titleHorizontalPadding: CGFloat = 150
    static let trailingControlWidth: CGFloat = 126
    static let iconButtonSize: CGFloat = 28
    static let overflowButtonWidth: CGFloat = 36
    static let inactiveIconOpacity: CGFloat = 0.72
    static let usesAppKitOverflowMenu = true
    static let titleTextStartsRename = false
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
            titleBar
                .background {
                    toolbarBackground
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(NotchPilotTheme.islandDivider)
                        .frame(height: 1)
                }

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
            .background(editorBackground)

            if missingExternalFileCount > 0 {
                Label(
                    AppStrings.missingExternalFiles(count: missingExternalFileCount, language: language),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchPilotTheme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(statusBackground)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchPilotTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(statusBackground)
            }
        }
        .background {
            windowBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NotchPilotTheme.islandHairline)
        }
        .foregroundStyle(NotchPilotTheme.islandTextPrimary)
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

    private var titleBar: some View {
        ZStack {
            Text(viewModel.selectedNote?.title ?? ScratchpadNote.untitledTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPilotTheme.islandTextSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, ScratchpadStandaloneWindowChromeMetrics.titleHorizontalPadding)

            HStack(spacing: 8) {
                Spacer()
                pinButton
                overflowMenu
            }
            .padding(.trailing, 16)
        }
        .frame(height: ScratchpadStandaloneWindowChromeMetrics.titleBarHeight)
    }

    private var pinButton: some View {
        Button {
            isPinned.toggle()
            onTogglePinned(isPinned)
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .frame(
                    width: ScratchpadStandaloneWindowChromeMetrics.iconButtonSize,
                    height: ScratchpadStandaloneWindowChromeMetrics.iconButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPinned ? NotchPilotTheme.notes : chromeIconForeground)
        .help(AppStrings.text(.keepOnTop, language: language))
    }

    private var overflowMenu: some View {
        ScratchpadTitlebarOverflowMenuButton(
            foregroundColor: NSColor.white.withAlphaComponent(ScratchpadStandaloneWindowChromeMetrics.inactiveIconOpacity),
            renameTitle: AppStrings.text(.renameNote, language: language),
            openFolderTitle: AppStrings.text(.openNoteFolder, language: language),
            deleteTitle: AppStrings.text(.deleteNote, language: language),
            onRename: beginRename,
            onOpenFolder: revealNoteFolder,
            onDelete: {
                isDeleteConfirmationPresented = true
            }
        )
        .frame(
            width: ScratchpadStandaloneWindowChromeMetrics.overflowButtonWidth,
            height: ScratchpadStandaloneWindowChromeMetrics.iconButtonSize
        )
    }

    private var chromeIconForeground: Color {
        Color.white.opacity(ScratchpadStandaloneWindowChromeMetrics.inactiveIconOpacity)
    }

    private var windowBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.125, blue: 0.15).opacity(0.94),
                    Color(red: 0.045, green: 0.048, blue: 0.06).opacity(0.96),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var toolbarBackground: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.055))
            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.012),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var editorBackground: some View {
        Color(red: 0.042, green: 0.046, blue: 0.058)
            .opacity(0.9)
    }

    private var statusBackground: some View {
        Color.black.opacity(0.18)
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

private struct ScratchpadTitlebarOverflowMenuButton: NSViewRepresentable {
    let foregroundColor: NSColor
    let renameTitle: String
    let openFolderTitle: String
    let deleteTitle: String
    let onRename: () -> Void
    let onOpenFolder: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        configure(button)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func configure(_ button: NSButton) {
        button.image = Self.makeIcon(color: foregroundColor)
        button.contentTintColor = foregroundColor
        button.toolTip = renameTitle
    }

    private static func makeIcon(color: NSColor) -> NSImage {
        let size = NSSize(
            width: ScratchpadStandaloneWindowChromeMetrics.overflowButtonWidth,
            height: ScratchpadStandaloneWindowChromeMetrics.iconButtonSize
        )
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        color.setFill()
        let dotRadius: CGFloat = 1.7
        let centerY = size.height / 2
        for centerX in [10, 15, 20] as [CGFloat] {
            NSBezierPath(
                ovalIn: NSRect(
                    x: centerX - dotRadius,
                    y: centerY - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
            ).fill()
        }

        color.setStroke()
        let chevron = NSBezierPath()
        chevron.lineWidth = 1.8
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.move(to: NSPoint(x: size.width - 10, y: centerY + 2))
        chevron.line(to: NSPoint(x: size.width - 6, y: centerY - 2))
        chevron.line(to: NSPoint(x: size.width - 2, y: centerY + 2))
        chevron.stroke()

        return image
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScratchpadTitlebarOverflowMenuButton

        init(parent: ScratchpadTitlebarOverflowMenuButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            addItem(title: parent.renameTitle, action: #selector(rename), to: menu)
            addItem(title: parent.openFolderTitle, action: #selector(openFolder), to: menu)
            menu.addItem(.separator())
            addItem(title: parent.deleteTitle, action: #selector(deleteNote), to: menu)

            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: sender)
            } else {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
            }
        }

        @objc private func rename() {
            parent.onRename()
        }

        @objc private func openFolder() {
            parent.onOpenFolder()
        }

        @objc private func deleteNote() {
            parent.onDelete()
        }

        private func addItem(title: String, action: Selector, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }
}
