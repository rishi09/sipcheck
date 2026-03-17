import SwiftUI

struct JournalEntryRow: View {
    let entry: JournalEntry

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: entry.dateLogged)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Beer thumbnail placeholder
            ZStack {
                Circle()
                    .fill(SipColors.surface)
                    .frame(width: 44, height: 44)
                Image(systemName: "mug.fill")
                    .font(.system(size: 18))
                    .foregroundColor(SipColors.primary)
            }

            // Beer name + style
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.beerName) \(entry.style.isEmpty ? "" : "- \(entry.style)")")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textPrimary)
                    .lineLimit(1)

                // Star rating
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= entry.rating ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(star <= entry.rating ? SipColors.starFilled : SipColors.starEmpty)
                    }

                    // "Not For Me" badge for low ratings
                    if entry.rating <= 2 {
                        Text("Not For Me")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(SipColors.destructive)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SipColors.destructive.opacity(0.15))
                            .cornerRadius(4)
                            .padding(.leading, 4)
                    }
                }
            }

            Spacer()

            // Date
            Text(formattedDate)
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
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
