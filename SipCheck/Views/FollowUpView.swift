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
            VStack(spacing: SipSpacing.m) {
                // SRM style tile — the beer's color, not a stock glyph
                RoundedRectangle(cornerRadius: SipRadius.card, style: .continuous)
                    .fill(StyleGradient.gradient(for: scan.style))
                    .frame(width: 72, height: 72)
                    .padding(.top, SipSpacing.xxl)

                Text(scan.beerName)
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
                    .multilineTextAlignment(.center)

                VerdictBadge(verdict: scan.verdict)
            }
            .padding(.horizontal, SipSpacing.xl)
            .padding(.bottom, SipSpacing.s)

            // Beer metadata
            if let meta = beerMetadata {
                Text(meta)
                    .font(SipTypography.subhead)
                    .foregroundColor(SipColors.textSecondary)
                    .padding(.bottom, SipSpacing.xl)
            }

            Divider()
                .padding(.horizontal, SipSpacing.xl)

            // Question
            Text("Did you end up trying this one?")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SipSpacing.xl)
                .padding(.vertical, SipSpacing.xl)

            // Action buttons
            VStack(spacing: SipSpacing.m) {
                // Yes, I tried it — teal, not verdict green (traffic colors are answers, not chrome)
                Button("Yes, I tried it") {
                    let prefill = AddBeerPrefill(
                        name: scan.beerName,
                        style: scan.style ?? BeerStyle.other.rawValue,
                        abv: scan.abv,
                        scanId: scan.id
                    )
                    onTried?(prefill)
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .accessibilityIdentifier("followUpTriedIt")

                // Not yet
                Button("Not yet") {
                    onNotYet?()
                }
                .buttonStyle(SipSecondaryButtonStyle())
                .accessibilityIdentifier("followUpNotYet")

                // Not going to
                Button("Not going to") {
                    onNotGoing?()
                }
                .buttonStyle(SipQuietButtonStyle())
                .accessibilityIdentifier("followUpNotGoing")
            }
            .padding(.horizontal, SipSpacing.xl)

            Spacer()
        }
        .background(
            // Sheet surface separation: one step above the canvas
            SipColors.surface
                .ignoresSafeArea()
        )
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
