import SwiftUI

@main
struct SipCheckApp: App {
    @StateObject private var drinkStore = DrinkStore()

    init() {
        print("🍺 SipCheck app launched successfully!")
        print("📊 Loaded \(DrinkStore().drinks.count) drinks from storage")
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(drinkStore)
        }
    }
}
