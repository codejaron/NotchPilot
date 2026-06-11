import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
protocol DesktopLyricsMouseMonitoring: AnyObject {
    func start(onMouseActivity: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class DesktopLyricsMouseMonitor: DesktopLyricsMouseMonitoring {
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var onMouseActivity: (@MainActor () -> Void)?

    func start(onMouseActivity: @escaping @MainActor () -> Void) {
        self.onMouseActivity = onMouseActivity

        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel,
            .swipe,
        ]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.onMouseActivity?()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onMouseActivity?()
            }
        }
    }

    func stop() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        onMouseActivity = nil
    }
}

@MainActor
final class DesktopLyricsManager {
    private let nowPlayingController: SharedNowPlayingController
    private let settingsStore: SettingsStore
    private let controller: DesktopLyricsController
    private let searchProvider: LyricsSearching
    private let cache: LyricsCaching
    private let fileManager: FileManager
    private let lyricsSearchWindowController: LyricsSearchWindowController
    private let mouseMonitor: DesktopLyricsMouseMonitoring

    private static let lineRefreshTolerance: TimeInterval = 0.02

    private var windows: [String: DesktopLyricsWindow] = [:]
    private var playbackCancellable: AnyCancellable?
    private var presentationCancellable: AnyCancellable?
    private var desktopLyricsEnabledCancellable: AnyCancellable?
    private var lineRefreshTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var isStarted = false
    private var isNowPlayingMonitoringRequested = false
    private var isMouseMonitoringRequested = false
    private var lastActiveScreenID: String?

    init(
        nowPlayingController: SharedNowPlayingController,
        settingsStore: SettingsStore = .shared,
        provider: CachedLyricsProvider,
        searchProvider: LyricsSearching,
        cache: LyricsCaching,
        ignoredTrackStore: LyricsTrackIgnoring,
        mouseMonitor: DesktopLyricsMouseMonitoring = DesktopLyricsMouseMonitor(),
        fileManager: FileManager = .default,
        lyricsSearchWindowController: LyricsSearchWindowController = .init()
    ) {
        self.nowPlayingController = nowPlayingController
        self.settingsStore = settingsStore
        self.searchProvider = searchProvider
        self.cache = cache
        self.controller = DesktopLyricsController(
            settingsStore: settingsStore,
            provider: provider,
            cache: cache,
            ignoredTrackStore: ignoredTrackStore,
            playbackTimeProvider: { snapshot in
                nowPlayingController.currentPlaybackTime(for: snapshot.source)
            }
        )
        self.fileManager = fileManager
        self.lyricsSearchWindowController = lyricsSearchWindowController
        self.mouseMonitor = mouseMonitor
    }

    func start() {
        guard isStarted == false else {
            syncNowPlayingMonitoring()
            syncMouseMonitoring()
            return
        }
        isStarted = true
        synchronizeScreens()
        desktopLyricsEnabledCancellable = settingsStore.$desktopLyricsEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.syncNowPlayingMonitoring(desktopLyricsEnabled: isEnabled)
                self?.syncMouseMonitoring(desktopLyricsEnabled: isEnabled)
                self?.refreshWindows()
            }
        syncNowPlayingMonitoring()
        syncMouseMonitoring()
        controller.handlePlaybackState(nowPlayingController.currentState)

        playbackCancellable = nowPlayingController.$currentState.sink { [weak self] state in
            self?.controller.handlePlaybackState(state)
            self?.refreshWindows()
        }

        presentationCancellable = controller.$presentation.sink { [weak self] presentation in
            self?.refreshWindows()
            self?.scheduleLineRefresh(for: presentation)
        }

        scheduleLineRefresh(for: controller.presentation)

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
        guard isStarted else {
            return
        }
        isStarted = false
        syncNowPlayingMonitoring()
        desktopLyricsEnabledCancellable = nil
        lineRefreshTimer?.invalidate()
        lineRefreshTimer = nil
        syncMouseMonitoring()
        playbackCancellable = nil
        presentationCancellable = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        windows.values.forEach { $0.close() }
        windows.removeAll()
    }

    private func syncNowPlayingMonitoring(desktopLyricsEnabled: Bool? = nil) {
        let shouldMonitor = isStarted && (desktopLyricsEnabled ?? settingsStore.desktopLyricsEnabled)
        guard shouldMonitor != isNowPlayingMonitoringRequested else {
            return
        }

        isNowPlayingMonitoringRequested = shouldMonitor
        if shouldMonitor {
            nowPlayingController.start()
            controller.handlePlaybackState(nowPlayingController.currentState)
        } else {
            nowPlayingController.stop()
            controller.handlePlaybackState(.idle)
        }
    }

    private func syncMouseMonitoring(desktopLyricsEnabled: Bool? = nil) {
        let shouldMonitor = isStarted && (desktopLyricsEnabled ?? settingsStore.desktopLyricsEnabled)
        guard shouldMonitor != isMouseMonitoringRequested else {
            return
        }

        isMouseMonitoringRequested = shouldMonitor
        if shouldMonitor {
            mouseMonitor.start { [weak self] in
                guard let self, self.isStarted else {
                    return
                }
                self.refreshWindows()
            }
        } else {
            mouseMonitor.stop()
        }
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
            descriptors: NSScreen.screens.compactMap(screenDescriptor(for:)),
            fallbackID: lastActiveScreenID
        )
        if let activeScreenID {
            lastActiveScreenID = activeScreenID
        }

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
                window.update(
                    presentation: controller.presentation,
                    visibleFrame: screen.visibleFrame,
                    mouseLocation: mouseLocation,
                    highlightColor: highlightColor,
                    fontSize: fontSize
                )
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }
    }

    private func scheduleLineRefresh(for presentation: DesktopLyricsPresentation) {
        lineRefreshTimer?.invalidate()
        lineRefreshTimer = nil

        guard presentation.isVisible,
              let nextLineStartDate = presentation.lineState?.nextLineStartDate else {
            return
        }

        let fireDate = max(Date(), nextLineStartDate.addingTimeInterval(Self.lineRefreshTolerance))
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.lineRefreshTimer = nil
                self.controller.refreshPresentation()
                self.refreshWindows()
                self.scheduleLineRefresh(for: self.controller.presentation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        lineRefreshTimer = timer
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
        true
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
            },
            previewHandler: { [weak self] lyrics in
                self?.controller.previewLyricsOverride(lyrics, for: bindingSnapshot)
                self?.refreshWindows()
            },
            cancelPreviewHandler: { [weak self] in
                self?.controller.cancelLyricsOverridePreview(for: bindingSnapshot)
                self?.refreshWindows()
            }
        )
    }

    func ignoreCurrentTrackLyrics() {
        controller.ignoreCurrentTrackLyrics()
        refreshWindows()
    }

    func revealCurrentLyricsInFinder() {
        let url = controller.currentLyricsFileURL ?? cache.directoryURL

        if url.hasDirectoryPath {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
            return
        }

        if fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let directoryURL = url.deletingLastPathComponent()
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directoryURL)
        }
    }
}
