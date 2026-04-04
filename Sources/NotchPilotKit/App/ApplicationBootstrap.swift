import AppKit

@MainActor
public enum ApplicationBootstrap {
    private static let delegate = NotchPilotAppDelegate()

    public static func run() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}
