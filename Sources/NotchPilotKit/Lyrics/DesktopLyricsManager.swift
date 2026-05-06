import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class DesktopLyricsManager {
    private let nowPlayingController: SharedNowPlayingController
    private let settingsStore: SettingsStore
    private let controller: DesktopLyricsController
    private let searchProvider: LyricsSearching
    private let fileManager: FileManager
    private let lyricsSearchWindowController: LyricsSearchWindowController

    private var windows: [String: DesktopLyricsWindow] = [:]
    private var playbackCancellable: AnyCancellable?
    private var presentationCancellable: AnyCancellable?
    private var displayTimer: Timer?
    private var isHighRefreshActive = false
    private var screenObserver: NSObjectProtocol?

    init(
        nowPlayingController: SharedNowPlayingController,
        settingsStore: SettingsStore = .shared,
        provider: CachedLyricsProvider,
        searchProvider: LyricsSearching,
        cache: LyricsCaching,
        ignoredTrackStore: LyricsTrackIgnoring,
        fileManager: FileManager = .default,
        lyricsSearchWindowController: LyricsSearchWindowController = .init()
    ) {
        self.nowPlayingController = nowPlayingController
        self.settingsStore = settingsStore
        self.searchProvider = searchProvider
        self.controller = DesktopLyricsController(
            settingsStore: settingsStore,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore
        )
        self.fileManager = fileManager
        self.lyricsSearchWindowController = lyricsSearchWindowController
    }

    func start() {
        synchronizeScreens()
        nowPlayingController.start()
        controller.handlePlaybackState(nowPlayingController.currentState)

        playbackCancellable = nowPlayingController.$currentState.sink { [weak self] state in
            self?.controller.handlePlaybackState(state)
            self?.refreshWindows()
        }

        presentationCancellable = controller.$presentation.sink { [weak self] _ in
            self?.refreshWindows()
        }

        startSlowTimer()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.synchronizeScreens()
                self?.refreshWindows()
            }
        }

        refreshWindows()
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
        isHighRefreshActive = false
        playbackCancellable = nil
        presentationCancellable = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        windows.values.forEach { $0.close() }
        windows.removeAll()
        nowPlayingController.stop()
    }

    private func synchronizeScreens() {
        let screens = NSScreen.screens
        let descriptors = screens.compactMap(screenDescriptor(for:))
        let nextIDs = Set(descriptors.map(\.id))

        for descriptor in descriptors where windows[descriptor.id] == nil {
            windows[descriptor.id] = DesktopLyricsWindow()
        }

        for obsoleteID in Set(windows.keys).subtracting(nextIDs) {
            windows[obsoleteID]?.close()
            windows.removeValue(forKey: obsoleteID)
        }
    }

    private func refreshWindows() {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreenID = ActiveDesktopLyricsScreenResolver.resolve(
            mouseLocation: mouseLocation,
            descriptors: NSScreen.screens.compactMap(screenDescriptor(for:))
        )

        for screen in NSScreen.screens {
            guard let screenID = screenID(for: screen),
                  let window = windows[screenID] else {
                continue
            }

            let shouldShow =
                settingsStore.desktopLyricsEnabled &&
                controller.presentation.isVisible &&
                screenID == activeScreenID

            if shouldShow {
                let fontSize = CGFloat(settingsStore.desktopLyricsFontSize)
                let highlightColor = Color(hex: settingsStore.desktopLyricsHighlightColorHex) ?? .green
                let windowFrame = DesktopLyricsWindowLayout.frame(
                    in: screen.visibleFrame,
                    fontSize: fontSize
                )
                let isMouseHovering = windowFrame.contains(mouseLocation)
                window.update(
                    presentation: controller.presentation,
                    visibleFrame: screen.visibleFrame,
                    isMouseHovering: isMouseHovering,
                    highlightColor: highlightColor,
                    fontSize: fontSize
                )
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }

        updateRefreshRate()
    }

    private func updateRefreshRate() {
        let needsHighRefresh = controller.presentation.isVisible
        guard needsHighRefresh != isHighRefreshActive else { return }
        isHighRefreshActive = needsHighRefresh
        let interval: TimeInterval = needsHighRefresh ? 1.0 / 60.0 : 0.25
        scheduleTimer(interval: interval)
    }

    private func startSlowTimer() {
        scheduleTimer(interval: 0.25)
    }

    private func scheduleTimer(interval: TimeInterval) {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.controller.refreshPresentation()
                self?.refreshWindows()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func screenDescriptor(for screen: NSScreen) -> ScreenDescriptor? {
        guard let id = screenID(for: screen) else {
            return nil
        }

        return ScreenDescriptor(
            id: id,
            frame: screen.frame,
            isPrimary: screen == NSScreen.main,
            closedNotchSize: nil
        )
    }

    private func screenID(for screen: NSScreen) -> String? {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(screenNumber.uint32Value)
        }

        return screen.localizedName
    }

    var canIgnoreCurrentTrackLyrics: Bool {
        controller.canIgnoreCurrentTrackLyrics
    }

    var canSearchCurrentTrackLyrics: Bool {
        controller.canSearchCurrentTrackLyrics
    }

    var canRevealCurrentLyricsInFinder: Bool {
        controller.currentLyricsFileURL != nil
    }

    var canAdjustLyricsOffset: Bool {
        controller.canAdjustLyricsOffset
    }

    var currentLyricsOffset: Int {
        controller.currentOffsetMilliseconds
    }

    func setLyricsOffset(_ milliseconds: Int) {
        controller.setLyricsOffset(milliseconds)
        refreshWindows()
    }

    func showLyricsSearchWindow() {
        guard let bindingSnapshot = controller.currentSearchSnapshot else {
            return
        }

        lyricsSearchWindowController.showSearch(
            bindingSnapshot: bindingSnapshot,
            searchProvider: searchProvider,
            applyHandler: { [weak self] lyrics in
                self?.controller.applyLyricsOverride(lyrics, for: bindingSnapshot)
                self?.refreshWindows()
            }
        )
    }

    func ignoreCurrentTrackLyrics() {
        controller.ignoreCurrentTrackLyrics()
        refreshWindows()
    }

    func revealCurrentLyricsInFinder() {
        guard let url = controller.currentLyricsFileURL else {
            return
        }

        if fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
