import SwiftUI

struct GeneralSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text("Hover behavior, animation speed, and other preferences will appear here.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
