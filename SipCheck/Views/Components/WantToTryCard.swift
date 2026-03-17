import SwiftUI

struct WantToTryCard: View {
    let scan: Scan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Beer icon placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(SipColors.surface)
                .frame(width: 100, height: 80)
                .overlay(
                    Image(systemName: "mug.fill")
                        .font(.system(size: 28))
                        .foregroundColor(SipColors.primary)
                )

            // Beer name
            Text(scan.beerName)
                .font(SipTypography.subhead)
                .foregroundColor(SipColors.textPrimary)
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)

            // Style
            if let style = scan.style {
                Text(style)
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textSecondary)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
            }
        }
        .frame(width: 100)
    }
}

struct WantToTryCard_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            WantToTryCard(scan: Scan(
                beerName: "Pliny the Elder",
                style: "Imperial IPA",
                verdict: .tryIt,
                wantToTry: true
            ))
            WantToTryCard(scan: Scan(
                beerName: "Westvleteren 12",
                style: "Belgian Quad",
                verdict: .tryIt,
                wantToTry: true
            ))
        }
        .padding()
        .background(SipColors.background)
        .previewDisplayName("Want to Try Cards")
    }
}
