import SwiftUI

struct RatingPicker: View {
    @Binding var rating: Rating

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Rating.allCases, id: \.self) { ratingOption in
                Button {
                    rating = ratingOption
                } label: {
                    VStack(spacing: 4) {
                        Text(ratingOption.emoji)
                            .font(.system(size: 40))
                        Text(ratingOption.displayName)
                            .font(.caption)
                            .foregroundColor(rating == ratingOption ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(rating == ratingOption ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(rating == ratingOption ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
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
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
