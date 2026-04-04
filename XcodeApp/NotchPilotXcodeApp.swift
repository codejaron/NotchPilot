import SwiftUI
import NotchPilotKit

@main
struct NotchPilotXcodeApp: App {
    @NSApplicationDelegateAdaptor(NotchPilotAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("NotchPilot") {
            LaunchStatusView()
        }
        .defaultSize(width: 460, height: 260)

        Settings {
            EmptyView()
        }
    }
}

private struct LaunchStatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("NotchPilot Is Running")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("The app now launches as a real macOS app bundle. Hover near the top-center notch area or click it to open.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Hover or click near the top-center notch area", systemImage: "capsule")
                Label("Use the menu bar item named NotchPilot", systemImage: "menubar.rectangle")
                Label("Send a hook event with Bridge/notch-bridge.py", systemImage: "terminal")
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))

            HStack(spacing: 12) {
                Button("Quit NotchPilot") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
