import SwiftUI

struct JournalTabView: View {
    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundColor(SipColors.textPrimary)

                Text("Journal")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
            }
        }
        .accessibilityIdentifier("journalTab")
    }
}

struct JournalTabView_Previews: PreviewProvider {
    static var previews: some View {
        JournalTabView()
    }
}
