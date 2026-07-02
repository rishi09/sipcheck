import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Every tab root takes .sipTabBarClearance() — the ONE shared
            // bottom-inset contract (safeAreaInset + fade scrim) that keeps
            // content clear of the floating bar. The old per-screen 110pt
            // paddings are gone; do not reintroduce them (round-2 crit #1).
            CheckTabView()
                .sipTabBarClearance()
                .tabItem {
                    Label("Check", systemImage: "camera.viewfinder")
                }
                .tag(0)

            JournalTabView()
                .sipTabBarClearance()
                .tabItem {
                    Label("Journal", systemImage: "book.closed")
                }
                .tag(1)

            ProfileTabView()
                .sipTabBarClearance()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        // Native TabView: on iOS 26 the floating Liquid Glass bar comes free —
        // do NOT add UITabBarAppearance or bar backgrounds (would break it).
        // The E2E bridge assumes the bar at y≈584–646 on a 375×667pt screen;
        // .tabBarMinimizeBehavior(.onScrollDown) stays deferred for that reason.
        .tint(SipColors.accent)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
