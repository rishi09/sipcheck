import SwiftUI

struct CheckTabView: View {
    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundColor(SipColors.textPrimary)

                Text("Check")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
            }
        }
        .accessibilityIdentifier("checkTab")
    }
}

struct CheckTabView_Previews: PreviewProvider {
    static var previews: some View {
        CheckTabView()
    }
}
