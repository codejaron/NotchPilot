import AppKit
import SwiftUI

@MainActor
final class LyricsSearchController: ObservableObject {
    @Published var searchTitle: String
    @Published var searchArtist: String
    @Published private(set) var results: [LyricsSearchCandidate] = []
    @Published var selectedResultID: LyricsSearchCandidate.ID?
    @Published private(set) var selectedLyrics: TimedLyrics?
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    let bindingSnapshot: MediaPlaybackSnapshot

    private let searchProvider: LyricsSearching
    private let applyHandler: (TimedLyrics) -> Void

    init(
        bindingSnapshot: MediaPlaybackSnapshot,
        searchProvider: LyricsSearching,
        applyHandler: @escaping (TimedLyrics) -> Void
    ) {
        self.bindingSnapshot = bindingSnapshot
        self.searchProvider = searchProvider
        self.applyHandler = applyHandler
        self.searchTitle = bindingSnapshot.title
        self.searchArtist = bindingSnapshot.artist
    }

    var bindingDisplayTitle: String {
        [bindingSnapshot.artist, bindingSnapshot.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " - ")
    }

    private var selectedCandidate: LyricsSearchCandidate? {
        results.first(where: { $0.id == selectedResultID })
    }

    var canApplySelection: Bool {
        selectedLyrics != nil
    }

    var selectedPreviewText: String {
        guard let selectedLyrics else {
            return errorMessage ?? AppStrings.text(.noLyricsPreview, language: SettingsStore.shared.interfaceLanguage)
        }

        return selectedLyrics.lines
            .prefix(16)
            .map {
                if let translation = $0.translation {
                    return "\($0.text)\n\(translation)"
                }
                return $0.text
            }
            .joined(separator: "\n")
    }

    func search() async {
        isSearching = true
        errorMessage = nil

        let lyrics = await searchProvider.searchLyrics(
            title: searchTitle,
            artist: searchArtist,
            duration: bindingSnapshot.duration,
            limit: 40
        )

        results = lyrics
        selectedResultID = results.first?.id
        selectedLyrics = nil
        isSearching = false

        if results.isEmpty {
            errorMessage = AppStrings.text(.noLyricsFound, language: SettingsStore.shared.interfaceLanguage)
        } else {
            errorMessage = nil
        }
    }

    func loadSelectedLyrics() async {
        guard let selectedCandidate else {
            selectedLyrics = nil
            return
        }

        do {
            selectedLyrics = try await selectedCandidate.loadLyrics()
            errorMessage = nil
        } catch {
            selectedLyrics = nil
            errorMessage = AppStrings.text(.unableToLoadLyrics, language: SettingsStore.shared.interfaceLanguage)
        }
    }

    func applySelectedLyrics() {
        guard let selectedLyrics else {
            return
        }

        applyHandler(selectedLyrics)
    }
}

struct LyricsSearchView: View {
    @ObservedObject var controller: LyricsSearchController
    @ObservedObject private var store = SettingsStore.shared
    let closeWindow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.text(.lyricsBoundTo, language: store.interfaceLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.bindingDisplayTitle)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                Button(AppStrings.text(.close, language: store.interfaceLanguage)) {
                    closeWindow()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField(AppStrings.text(.song, language: store.interfaceLanguage), text: $controller.searchTitle)
                    TextField(AppStrings.text(.artist, language: store.interfaceLanguage), text: $controller.searchArtist)
                    Button(
                        controller.isSearching
                            ? AppStrings.text(.searching, language: store.interfaceLanguage)
                            : AppStrings.text(.search, language: store.interfaceLanguage)
                    ) {
                        Task {
                            await controller.search()
                        }
                    }
                    .disabled(controller.isSearching)
                }

                HSplitView {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text(AppStrings.text(.song, language: store.interfaceLanguage))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(AppStrings.text(.artist, language: store.interfaceLanguage))
                                .frame(width: 180, alignment: .leading)
                            Text(AppStrings.text(.source, language: store.interfaceLanguage))
                                .frame(width: 110, alignment: .leading)
                        }
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                        Divider()

                        List(selection: $controller.selectedResultID) {
                            ForEach(controller.results) { result in
                                HStack(spacing: 0) {
                                    Text(result.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(result.artist)
                                        .frame(width: 180, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    Text(result.service)
                                        .frame(width: 110, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .tag(result.id)
                            }
                        }
                    }
                    .frame(minWidth: 320, minHeight: 320)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let errorMessage = controller.errorMessage, controller.results.isEmpty {
                                Text(errorMessage)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(controller.selectedPreviewText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 360, minHeight: 320)
                    .background(Color(nsColor: .textBackgroundColor))
                }

                HStack {
                    if let errorMessage = controller.errorMessage, controller.results.isEmpty == false {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(AppStrings.text(.applyToCurrentSong, language: store.interfaceLanguage)) {
                        controller.applySelectedLyrics()
                        closeWindow()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.canApplySelection == false)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 920, minHeight: 500)
        .task {
            if controller.results.isEmpty {
                await controller.search()
            }
        }
        .task(id: controller.selectedResultID) {
            if controller.selectedResultID != nil {
                await controller.loadSelectedLyrics()
            }
        }
    }
}

@MainActor
final class LyricsSearchWindowController {
    private var window: NSWindow?

    func showSearch(
        bindingSnapshot: MediaPlaybackSnapshot,
        searchProvider: LyricsSearching,
        applyHandler: @escaping (TimedLyrics) -> Void
    ) {
        let controller = LyricsSearchController(
            bindingSnapshot: bindingSnapshot,
            searchProvider: searchProvider,
            applyHandler: applyHandler
        )
        let rootView = LyricsSearchView(controller: controller) { [weak self] in
            self?.window?.close()
        }

        if let window {
            window.contentView = NSHostingView(rootView: rootView)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppStrings.text(.searchLyricsWindowTitle, language: SettingsStore.shared.interfaceLanguage)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
