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
    private(set) var performedActions: [(CodexSurfaceAction, String)] = []
    private(set) var selectedOptions: [(String, String)] = []
    private(set) var updatedTexts: [(String, String)] = []
    private(set) var focusedThreadIDs: [String] = []
    private var currentSurface: CodexActionableSurface?

    func start() {}
    func stop() {}

    @discardableResult
    func focusThread(id: String) -> Bool {
        focusedThreadIDs.append(id)
        return true
    }

    @discardableResult
    func perform(action: CodexSurfaceAction, on surfaceID: String) -> Bool {
        guard currentSurface?.id == surfaceID else {
            return false
        }
        performedActions.append((action, surfaceID))
        currentSurface = nil
        return true
    }

    @discardableResult
    func selectOption(_ optionID: String, on surfaceID: String) -> Bool {
        guard currentSurface?.id == surfaceID else {
            return false
        }
        selectedOptions.append((optionID, surfaceID))
        return true
    }

    @discardableResult
    func updateText(_ text: String, on surfaceID: String) -> Bool {
        guard currentSurface?.id == surfaceID else {
            return false
        }
        updatedTexts.append((text, surfaceID))
        return true
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
        currentSurface = surface
        onSurfaceChanged?(surface)
    }
}
