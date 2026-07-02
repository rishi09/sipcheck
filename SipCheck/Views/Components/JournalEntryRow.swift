import SwiftUI

struct JournalEntryRow: View {
    let entry: JournalEntry

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: entry.dateLogged)
    }

    var body: some View {
        HStack(spacing: SipSpacing.m) {
            // SRM style tile — the beer's color is the thumbnail
            RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                .fill(StyleGradient.gradient(for: entry.style.isEmpty ? nil : entry.style))
                .frame(width: 44, height: 44)

            // Name on line 1; style + rating share the metadata baseline
            VStack(alignment: .leading, spacing: SipSpacing.xs) {
                Text(entry.beerName)
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: SipSpacing.s) {
                    if !entry.style.isEmpty {
                        Text(entry.style)
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textSecondary)
                            .lineLimit(1)
                    }

                    // Star rating
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= entry.rating ? "star.fill" : "star")
                                .font(SipTypography.caption)
                                .foregroundColor(star <= entry.rating ? SipColors.starFilled : SipColors.starEmpty)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rated \(entry.rating) of 5")

                    // "Not For Me" badge for low ratings
                    if entry.rating <= 2 {
                        Text("Not For Me")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(SipColors.verdictSkip)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                                    .fill(SipColors.verdictSkip.opacity(0.15))
                            )
                    }
                }
            }

            Spacer()

            // Date
            Text(formattedDate)
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
        }
        .padding(.vertical, SipSpacing.s)
        .padding(.horizontal, SipSpacing.l)
    }
}

struct JournalEntryRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            JournalEntryRow(entry: JournalEntry(
                beerName: "Sierra Nevada Pale Ale",
                brand: "Sierra Nevada",
                style: "American Pale Ale",
                rating: 5
            ))
            JournalEntryRow(entry: JournalEntry(
                beerName: "Guinness Draught",
                brand: "Guinness",
                style: "Irish Dry Stout",
                rating: 4
            ))
            JournalEntryRow(entry: JournalEntry(
                beerName: "Bud Light",
                brand: "Anheuser-Busch",
                style: "Light Lager",
                rating: 2
            ))
        }
        .background(SipColors.background)
        .previewDisplayName("Journal Entry Rows")
    }
}
