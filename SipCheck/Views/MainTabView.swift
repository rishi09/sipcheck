import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CheckTabView()
                .tabItem {
                    Label("Check", systemImage: "camera.viewfinder")
                }
                .tag(0)

            JournalTabView()
                .tabItem {
                    Label("Journal", systemImage: "book.closed")
                }
                .tag(1)

            ProfileTabView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        .tint(SipColors.primary)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
