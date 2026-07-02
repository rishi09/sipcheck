import SwiftUI

struct RatingPicker: View {
    @Binding var rating: Rating

    // Hero-ish glyph size scales with Dynamic Type (no hardcoded .system(size:)).
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 36

    /// Tinted SF symbols instead of raw emoji (crit watchlist: no raw 👍 next
    /// to semantic color). View-layer mapping only — Rating.emoji is untouched
    /// for any other consumer.
    private func symbolName(for ratingOption: Rating) -> String {
        switch ratingOption {
        case .like:    return "hand.thumbsup.fill"
        case .neutral: return "hand.raised.fill"
        case .dislike: return "hand.thumbsdown.fill"
        }
    }

    var body: some View {
        HStack(spacing: SipSpacing.l) {
            ForEach(Rating.allCases, id: \.self) { ratingOption in
                Button {
                    rating = ratingOption
                } label: {
                    VStack(spacing: SipSpacing.xs) {
                        Image(systemName: symbolName(for: ratingOption))
                            .font(.system(size: symbolSize))
                            .foregroundColor(rating == ratingOption ? SipColors.accent : SipColors.textSecondary)
                        Text(ratingOption.displayName)
                            .font(SipTypography.caption)
                            .foregroundColor(rating == ratingOption ? SipColors.textPrimary : SipColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SipSpacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                            .fill(rating == ratingOption ? SipColors.accentSubtle : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                            .stroke(rating == ratingOption ? SipColors.accent : SipColors.starEmpty, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.25), value: rating)
                .accessibilityLabel(ratingOption.displayName)
                .accessibilityIdentifier("rating_\(ratingOption.rawValue)")
            }
        }
    }
}

struct RatingPicker_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State var rating: Rating = .neutral

        var body: some View {
            RatingPicker(rating: $rating)
                .padding()
                .background(SipColors.background)
                .preferredColorScheme(.dark)
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
