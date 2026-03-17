import SwiftUI

struct SettingsTabView: View {
    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "gearshape")
                    .font(.system(size: 48))
                    .foregroundColor(SipColors.textPrimary)

                Text("Settings")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
            }
        }
        .accessibilityIdentifier("settingsTab")
    }
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
    }
}
