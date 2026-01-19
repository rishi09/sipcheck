import SwiftUI

struct StylePicker: View {
    @Binding var selectedStyle: String

    var body: some View {
        Picker("Style", selection: $selectedStyle) {
            ForEach(BeerStyle.allCases, id: \.self) { style in
                Text(style.displayName).tag(style.rawValue)
            }
        }
    }
}

struct StylePicker_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State var style: String = BeerStyle.ipa.rawValue

        var body: some View {
            Form {
                StylePicker(selectedStyle: $style)
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
