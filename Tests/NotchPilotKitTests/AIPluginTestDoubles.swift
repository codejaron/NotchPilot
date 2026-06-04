import AppKit
import XCTest
@testable import NotchPilotKit

final class SplitResponseBox: @unchecked Sendable {
    var data: Data?
}

@MainActor
final class SplitEventRecorder {
    var events: [NotchEvent] = []
}

final class SplitFakeCodexContextMonitor: @unchecked Sendable, CodexDesktopContextMonitoring, CodexDesktopActionableSurfaceMonitoring {
    var onThreadContextChanged: (@Sendable (CodexThreadUpdate) -> Void)?
    var onConnectionStateChanged: (@Sendable (CodexDesktopConnectionState) -> Void)?
    var onSurfaceChanged: (@Sendable (CodexActionableSurface?) -> Void)?
    private let storage = NSLock()
    private var storedStartCount = 0
    private var storedStopCount = 0
    private var storedPerformedActions: [(CodexSurfaceAction, String)] = []
    private var storedSelectedOptions: [(String, String)] = []
    private var storedUpdatedTexts: [(String, String)] = []
    private var storedFocusedThreadIDs: [String] = []
    private var currentSurface: CodexActionableSurface?

    var startCount: Int { withStorageLock { storedStartCount } }
    var stopCount: Int { withStorageLock { storedStopCount } }
    var performedActions: [(CodexSurfaceAction, String)] { withStorageLock { storedPerformedActions } }
    var selectedOptions: [(String, String)] { withStorageLock { storedSelectedOptions } }
    var updatedTexts: [(String, String)] { withStorageLock { storedUpdatedTexts } }
    var focusedThreadIDs: [String] { withStorageLock { storedFocusedThreadIDs } }

    func start() {
        withStorageLock {
            storedStartCount += 1
        }
    }

    func stop() {
        withStorageLock {
            storedStopCount += 1
        }
    }

    @discardableResult
    func focusThread(id: String) -> Bool {
        withStorageLock {
            storedFocusedThreadIDs.append(id)
        }
        return true
    }

    @discardableResult
    func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool {
        withStorageLock {
            guard currentSurface?.id == surfaceID else {
                return false
            }
            storedPerformedActions.append((action, surfaceID))
            currentSurface = nil
            return true
        }
    }

    @discardableResult
    func selectOption(_ optionID: String, on surfaceID: String) -> Bool {
        withStorageLock {
            guard currentSurface?.id == surfaceID else {
                return false
            }
            storedSelectedOptions.append((optionID, surfaceID))
            return true
        }
    }

    @discardableResult
    func updateText(_ text: String, on surfaceID: String) -> Bool {
        withStorageLock {
            guard currentSurface?.id == surfaceID else {
                return false
            }
            storedUpdatedTexts.append((text, surfaceID))
            return true
        }
    }

    func emit(update: CodexThreadUpdate) {
        onThreadContextChanged?(update)
    }

    func emit(
        context: CodexThreadContext,
        marksActivity: Bool = true
    ) {
        onThreadContextChanged?(CodexThreadUpdate(context: context, marksActivity: marksActivity))
    }

    func emit(connection: CodexDesktopConnectionState) {
        onConnectionStateChanged?(connection)
    }

    func emit(surface: CodexActionableSurface?) {
        withStorageLock {
            currentSurface = surface
        }
        onSurfaceChanged?(surface)
    }

    private func withStorageLock<T>(_ body: () -> T) -> T {
        storage.lock()
        defer { storage.unlock() }
        return body()
    }
}
