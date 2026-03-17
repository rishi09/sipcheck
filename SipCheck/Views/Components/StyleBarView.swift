import SwiftUI

struct StyleBarView: View {
    let style: String
    let percentage: Double
    let maxPercentage: Double

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SipColors.surface)
                        .frame(height: 24)

                    // Filled bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SipColors.primary)
                        .frame(
                            width: maxPercentage > 0
                                ? max(geometry.size.width * CGFloat(percentage / maxPercentage), 30)
                                : 30,
                            height: 24
                        )

                    // Percentage text inside bar
                    Text("\(Int(percentage))%")
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.background)
                        .fontWeight(.semibold)
                        .padding(.leading, 8)
                }
            }
            .frame(height: 24)

            // Style name on the right
            Text(style)
                .font(SipTypography.subhead)
                .foregroundColor(SipColors.textPrimary)
                .frame(width: 80, alignment: .leading)
        }
    }
}

struct StyleBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            StyleBarView(style: "IPA", percentage: 68, maxPercentage: 68)
            StyleBarView(style: "Pale Ale", percentage: 15, maxPercentage: 68)
            StyleBarView(style: "Stout", percentage: 10, maxPercentage: 68)
            StyleBarView(style: "Other", percentage: 7, maxPercentage: 68)
        }
        .padding()
        .background(SipColors.background)
        .previewDisplayName("Style Bars")
    }
}
