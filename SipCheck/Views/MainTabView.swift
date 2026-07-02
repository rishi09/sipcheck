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
        // Native TabView: on iOS 26 the floating Liquid Glass bar comes free —
        // do NOT add UITabBarAppearance or bar backgrounds (would break it).
        // TODO(glass-followup): adopt .tabBarMinimizeBehavior(.onScrollDown) +
        // .contentMargins(.bottom, for: .scrollContent) in a coordinated pass —
        // the E2E bridge assumes the bar at y≈584–646 and three views carry
        // 110pt bottom-clearance paddings that must migrate at the same time.
        .tint(SipColors.accent)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
