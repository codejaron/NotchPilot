import Combine
import SwiftUI

struct ScratchpadNotesDropIngestionResult: Equatable {
    let noteID: String
    let insertedCount: Int
    let failedCount: Int
}

@MainActor
public final class NotesPlugin: NotchPlugin, NotchPluginHeaderAccessoryRendering {
    public let id = "notes"
    public let title = "Notes"
    public let iconSystemName = "note.text"
    public let accentColor = NotchPilotTheme.notes
    public let dockOrder = 130

    @Published public var isEnabled: Bool

    private let settingsStore: SettingsStore
    let viewModel: ScratchpadNotesViewModel
    private let noteWindowController = ScratchpadNoteWindowController()
    private weak var bus: EventBus?
    private var settingsCancellables: Set<AnyCancellable> = []

    init(settingsStore: SettingsStore = .shared, store: ScratchpadStore = ScratchpadStore()) {
        self.settingsStore = settingsStore
        self.viewModel = ScratchpadNotesViewModel(store: store)
        self.isEnabled = settingsStore.notesEnabled

        settingsStore.$notesEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.isEnabled = isEnabled
                self?.objectWillChange.send()
            }
            .store(in: &settingsCancellables)

        settingsStore.$interfaceLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &settingsCancellables)
    }

    public func contentView(context: NotchContext) -> AnyView {
        AnyView(
            ScratchpadNotesRootView(
                viewModel: viewModel
            )
        )
    }

    var headerAccessoryPlacement: NotchPluginHeaderAccessoryPlacement {
        .contentTop
    }

    func headerAccessory(context: NotchContext, isOpenPinned: Bool) -> AnyView? {
        AnyView(
            ScratchpadNotesHeaderAccessory(
                viewModel: viewModel,
                isOpenPinned: isOpenPinned,
                onTogglePin: { [weak self] in
                    self?.toggleNotchPin(isCurrentlyPinned: isOpenPinned, screenID: context.screenID)
                },
                onPopOut: { [weak self] note in
                    self?.popOut(note: note, screenID: context.screenID)
                }
            )
        )
    }

    public func activate(bus: EventBus) {
        self.bus = bus
    }

    public func deactivate() {
        do {
            try viewModel.flushPendingSave()
        } catch {
            NSLog("NotchPilot failed to flush scratchpad notes on deactivate: \(error.localizedDescription)")
        }
        noteWindowController.flushPendingSaves()
        bus = nil
    }

    func toggleNotchPin(isCurrentlyPinned: Bool, screenID: String) {
        bus?.emit(.setOpenPinned(!isCurrentlyPinned, target: .screen(id: screenID)))
    }

    @discardableResult
    func ingestDroppedFiles(
        _ urls: [URL],
        now: Date = Date()
    ) throws -> ScratchpadNotesDropIngestionResult {
        let target = try viewModel.ensureDropTargetNote(now: now)
        var insertedCount = 0
        var failedCount = 0

        for url in urls {
            do {
                try viewModel.insertAttachment(
                    from: url,
                    isImage: ScratchpadNotesViewModel.isImageAttachment(url),
                    now: now
                )
                insertedCount += 1
            } catch {
                failedCount += 1
            }
        }

        try viewModel.flushPendingSave()
        return ScratchpadNotesDropIngestionResult(
            noteID: target.id,
            insertedCount: insertedCount,
            failedCount: failedCount
        )
    }

    private func popOut(note: ScratchpadNote, screenID: String) {
        do {
            try noteWindowController.show(noteID: note.id, store: viewModel.store)
            bus?.emit(.closeRequested(target: .screen(id: screenID)))
        } catch {
            NSLog("NotchPilot failed to pop out scratchpad note: \(error.localizedDescription)")
        }
    }
}
