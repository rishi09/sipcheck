import SwiftUI

struct ProfileTabView: View {
    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundColor(SipColors.textPrimary)

                Text("Profile")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
            }
        }
        .accessibilityIdentifier("profileTab")
    }
}

struct ProfileTabView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTabView()
    }
}
