import SwiftUI

/// Sheet shown when a user taps a follow-up notification or returns to a scan
struct FollowUpView: View {
    let scan: Scan
    var onTried: ((AddBeerPrefill) -> Void)?
    var onNotYet: (() -> Void)?
    var onNotGoing: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "mug.fill")
                    .font(.system(size: 48))
                    .foregroundColor(SipColors.primary)
                    .padding(.top, 32)

                Text(scan.beerName)
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
                    .multilineTextAlignment(.center)

                VerdictBadge(verdict: scan.verdict)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Beer metadata
            if let meta = beerMetadata {
                Text(meta)
                    .font(SipTypography.subhead)
                    .foregroundColor(SipColors.textSecondary)
                    .padding(.bottom, 24)
            }

            Divider()
                .padding(.horizontal, 24)

            // Question
            Text("Did you end up trying this one?")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)

            // Action buttons
            VStack(spacing: 12) {
                // Yes, I tried it
                Button(action: {
                    let prefill = AddBeerPrefill(
                        name: scan.beerName,
                        style: scan.style ?? BeerStyle.other.rawValue,
                        abv: scan.abv
                    )
                    onTried?(prefill)
                }) {
                    Text("Yes, I tried it")
                        .font(SipTypography.headline)
                        .foregroundColor(SipColors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(SipColors.verdictTryIt)
                        )
                }
                .accessibilityIdentifier("followUpTriedIt")

                // Not yet
                Button(action: {
                    onNotYet?()
                }) {
                    Text("Not yet")
                        .font(SipTypography.headline)
                        .foregroundColor(SipColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SipColors.primary, lineWidth: 2)
                        )
                }
                .accessibilityIdentifier("followUpNotYet")

                // Not going to
                Button(action: {
                    onNotGoing?()
                }) {
                    Text("Not going to")
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
                .accessibilityIdentifier("followUpNotGoing")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(SipColors.background.ignoresSafeArea())
        .accessibilityIdentifier("followUpView")
    }

    private var beerMetadata: String? {
        var parts: [String] = []
        if let style = scan.style { parts.append(style) }
        if let abv = scan.abv { parts.append(String(format: "%.1f%% ABV", abv)) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}

struct FollowUpView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FollowUpView(
                scan: ScanStore.seedScans[0],
                onTried: { _ in },
                onNotYet: {},
                onNotGoing: {}
            )
            .previewDisplayName("Try It Scan")

            FollowUpView(
                scan: ScanStore.seedScans[1],
                onTried: { _ in },
                onNotYet: {},
                onNotGoing: {}
            )
            .previewDisplayName("Skip It Scan")
        }
    }
}
