import AppKit

enum NotchPilotWindowForegroundPresenter {
    enum PresentationStep: Equatable {
        case activateCurrentApplication
        case orderFrontRegardless
        case makeKeyAndOrderFront
    }

    static func presentationSteps(isApplicationActive: Bool) -> [PresentationStep] {
        if isApplicationActive {
            return [.orderFrontRegardless, .makeKeyAndOrderFront]
        }

        return [.activateCurrentApplication, .orderFrontRegardless, .makeKeyAndOrderFront]
    }

    @MainActor
    static func present(_ window: NSWindow) {
        for step in presentationSteps(isApplicationActive: NSApp.isActive) {
            perform(step, on: window)
        }
    }

    @MainActor
    private static func perform(_ step: PresentationStep, on window: NSWindow) {
        switch step {
        case .activateCurrentApplication:
            _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
        case .orderFrontRegardless:
            window.orderFrontRegardless()
        case .makeKeyAndOrderFront:
            window.makeKeyAndOrderFront(nil)
        }
    }
}
