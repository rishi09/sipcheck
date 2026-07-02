import SwiftUI

/// Horizontal percentage bar for the Profile "Top Styles" chart.
/// Bars scale against an absolute basis (maxPercentage defaults to 100 — WO-6
/// updates the caller) so bar length actually encodes the printed value, and
/// the fill is the style's SRM beer color, not brand teal (teal is reserved
/// for tappable chrome; the beer's own color is the only element that could
/// only belong to a beer app).
struct StyleBarView: View {
    let style: String
    let percentage: Double
    var maxPercentage: Double = 100

    /// "Other"/"Unknown" buckets have no beer color — the neutral SRM fallback
    /// would vanish against the surface track, so they get a quiet gray fill.
    private var barFill: AnyShapeStyle {
        if style == "Other" || style == "Unknown" {
            return AnyShapeStyle(SipColors.textSecondary.opacity(0.4))
        }
        return AnyShapeStyle(StyleGradient.gradient(for: style))
    }

    var body: some View {
        HStack(spacing: SipSpacing.s) {
            // Style name leads — it's the load-bearing datum.
            Text(style)
                .font(SipTypography.subhead)
                .foregroundColor(SipColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                        .fill(SipColors.surface)
                        .frame(height: 24)

                    // Filled bar — SRM beer color for the style (30pt floor so
                    // tiny slices stay visible). 1px hairline matches SRMSwatch
                    // so a stout bar never reads as an empty track (crit #3).
                    RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                        .fill(barFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .frame(
                            width: maxPercentage > 0
                                ? max(geometry.size.width * CGFloat(percentage / maxPercentage), 30)
                                : 30,
                            height: 24
                        )
                }
            }
            .frame(height: 24)

            // Percentage sits outside the bar: legible on every SRM fill
            // (dark text drowned on stout, light text glared on pilsner).
            Text("\(Int(percentage))%")
                .font(SipTypography.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(SipColors.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style), \(Int(percentage)) percent")
    }
}

struct StyleBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: SipSpacing.s) {
            StyleBarView(style: "IPA", percentage: 68)
            StyleBarView(style: "Pale Ale", percentage: 15)
            StyleBarView(style: "Stout", percentage: 10)
            StyleBarView(style: "Hefeweizen", percentage: 7)
            StyleBarView(style: "Other", percentage: 33, maxPercentage: 100)
        }
        .padding()
        .background(SipColors.background)
        .preferredColorScheme(.dark)
        .previewDisplayName("Style Bars")
    }
}
