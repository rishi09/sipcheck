import SwiftUI

struct AgeGateView: View {
    @AppStorage("hasConfirmedAge") private var hasConfirmedAge = false
    @State private var isLockedOut = false

    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon / logo area
                Image(systemName: "mug.fill")
                    .font(.system(size: 72))
                    .foregroundColor(SipColors.primary)

                // Headline + subtext
                VStack(spacing: 12) {
                    Text("SipCheck is for adults\n21 and older.")
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                        .multilineTextAlignment(.center)

                    if !isLockedOut {
                        Text("Please confirm your age to continue.")
                            .font(SipTypography.body)
                            .foregroundColor(SipColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                if isLockedOut {
                    // Locked state
                    VStack(spacing: 16) {
                        Image(systemName: "mug.fill")
                            .font(.system(size: 28))
                            .foregroundColor(SipColors.textSecondary)

                        Text("SipCheck is only available\nfor adults 21+.")
                            .font(SipTypography.body)
                            .foregroundColor(SipColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 60)
                } else {
                    // Buttons
                    VStack(spacing: 14) {
                        // Primary filled button
                        Button(action: {
                            hasConfirmedAge = true
                        }) {
                            Text("I'm 21 or Older")
                                .font(SipTypography.headline)
                                .foregroundColor(SipColors.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(SipColors.primary)
                                )
                        }

                        // Ghost / outline button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isLockedOut = true
                            }
                        }) {
                            Text("I'm Under 21")
                                .font(SipTypography.headline)
                                .foregroundColor(SipColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(SipColors.textSecondary.opacity(0.4), lineWidth: 1.5)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Preview

struct AgeGateView_Previews: PreviewProvider {
    static var previews: some View {
        AgeGateView()
            .previewDisplayName("Default")

        AgeGateView()
            .previewDisplayName("Locked Out")
    }
}
