import SwiftUI

struct VerdictBadge: View {
    let verdict: Verdict

    private var backgroundColor: Color {
        switch verdict {
        case .tryIt:
            return SipColors.verdictTryIt
        case .skipIt:
            return SipColors.verdictSkipIt
        case .yourCall:
            return SipColors.verdictYourCall
        }
    }

    private var displayText: String {
        switch verdict {
        case .tryIt:
            return "TRY IT"
        case .skipIt:
            return "SKIP IT"
        case .yourCall:
            return "YOUR CALL"
        }
    }

    var body: some View {
        Text(displayText)
            .font(SipTypography.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
    }
}

struct VerdictBadge_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            VerdictBadge(verdict: .tryIt)
            VerdictBadge(verdict: .skipIt)
            VerdictBadge(verdict: .yourCall)
        }
        .padding()
        .background(SipColors.background)
        .previewDisplayName("Verdict Badges")
    }
}
