import SwiftUI
import NotchPilotKit

@main
struct NotchPilotXcodeApp: App {
    @NSApplicationDelegateAdaptor(NotchPilotAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(selectedTab: .aiHooks)
        }
    }
}
