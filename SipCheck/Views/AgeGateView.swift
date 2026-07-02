import SwiftUI

struct AgeGateView: View {
    @AppStorage("hasConfirmedAge") private var hasConfirmedAge = false
    @State private var isLockedOut = false

    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 72
    @ScaledMetric(relativeTo: .title2) private var lockedIconSize: CGFloat = 28

    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            VStack(spacing: SipSpacing.xxl) {
                Spacer()

                // App icon / logo area
                Image(systemName: "mug.fill")
                    .font(.system(size: logoSize))
                    .foregroundColor(SipColors.accent)

                // Headline + subtext
                VStack(spacing: SipSpacing.m) {
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
                    VStack(spacing: SipSpacing.l) {
                        // Dimmed brand tint, not gray — a gray content glyph
                        // reads as template slop (crit watchlist Q1).
                        Image(systemName: "mug.fill")
                            .font(.system(size: lockedIconSize))
                            .foregroundColor(SipColors.accent.opacity(0.55))

                        Text("SipCheck is only available\nfor adults 21+.")
                            .font(SipTypography.body)
                            .foregroundColor(SipColors.textSecondary)
                            .multilineTextAlignment(.center)

                        // A mis-tap must not brick the app — offer a way back.
                        Button(action: {
                            withAnimation(.snappy(duration: 0.25)) {
                                isLockedOut = false
                            }
                        }) {
                            Text("I tapped by mistake — go back")
                        }
                        .buttonStyle(SipQuietButtonStyle())
                        .accessibilityIdentifier("ageGateGoBack")
                        .padding(.top, SipSpacing.s)
                    }
                    .padding(.bottom, 60)
                } else {
                    // Buttons
                    VStack(spacing: SipSpacing.l) {
                        // Primary filled button
                        Button(action: {
                            hasConfirmedAge = true
                        }) {
                            Text("I'm 21 or Older")
                        }
                        .buttonStyle(SipPrimaryButtonStyle())

                        // Ghost / outline button — stays muted, not brand teal.
                        Button(action: {
                            withAnimation(.snappy(duration: 0.25)) {
                                isLockedOut = true
                            }
                        }) {
                            Text("I'm Under 21")
                        }
                        .buttonStyle(SipSecondaryButtonStyle(tint: SipColors.textSecondary))
                    }
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.bottom, 60)
                }
            }
            .padding(.horizontal, SipSpacing.xl)
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
