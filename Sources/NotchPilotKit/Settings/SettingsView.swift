import SwiftUI

public struct SettingsView: View {
    public enum Tab: String, CaseIterable {
        case general = "General"
        case aiHooks = "AI Hooks"
    }

    @State private var selectedTab: Tab

    public init(selectedTab: Tab = .aiHooks) {
        _selectedTab = State(initialValue: selectedTab)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(Tab.general)

            AIHooksSettingsTab()
                .tabItem { Label("AI Hooks", systemImage: "sparkles") }
                .tag(Tab.aiHooks)
        }
        .frame(width: 560, height: 480)
    }
}
