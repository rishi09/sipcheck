import SwiftUI

struct WantToTryCard: View {
    let scan: Scan
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 6) {
                // Beer icon placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(SipColors.surface)
                    .frame(width: 100, height: 80)
                    .overlay(
                        ZStack {
                            Image(systemName: "mug.fill")
                                .font(.system(size: 28))
                                .foregroundColor(SipColors.primary)
                            // Verdict badge overlay
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    verdictBadge
                                        .padding(6)
                                }
                            }
                        }
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
        .buttonStyle(.plain)
    }

    private var verdictBadge: some View {
        let (text, color) = verdictInfo
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color)
            )
    }

    private var verdictInfo: (String, Color) {
        switch scan.verdict {
        case .tryIt:    return ("TRY IT", SipColors.verdictTryIt)
        case .skipIt:   return ("SKIP IT", SipColors.verdictSkipIt)
        case .yourCall: return ("YOUR CALL", SipColors.verdictYourCall)
        }
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
                verdict: .yourCall,
                wantToTry: true
            ))
        }
        .padding()
        .background(SipColors.background)
        .previewDisplayName("Want to Try Cards")
    }
}
