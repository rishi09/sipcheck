import SwiftUI

@main
struct SipCheckApp: App {
    @StateObject private var drinkStore: DrinkStore
    @StateObject private var scanStore: ScanStore
    @StateObject private var journalStore: JournalStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        let args = ProcessInfo.processInfo.arguments

        // --mock-ai: All AI service calls return fixed responses (no network)
        if args.contains("--mock-ai") {
            OpenAIService.useMockResponses = true
        }

        // --isolated-storage: Use temp directory instead of Documents
        // --seed-data: Load known test drinks on launch
        let useIsolatedStorage = args.contains("--isolated-storage")
        let useSeedData = args.contains("--seed-data")

        // Skip onboarding in isolated-storage test mode
        if useIsolatedStorage {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }

        if useIsolatedStorage {
            let testDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SipCheckTestStorage")
            try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
            _drinkStore = StateObject(wrappedValue: DrinkStore(storageDirectory: testDir, useSeedData: useSeedData))
            _scanStore = StateObject(wrappedValue: ScanStore(storageDirectory: testDir, useSeedData: useSeedData))
            _journalStore = StateObject(wrappedValue: JournalStore(storageDirectory: testDir, useSeedData: useSeedData))
        } else if useSeedData {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            _drinkStore = StateObject(wrappedValue: DrinkStore(storageDirectory: docsDir, useSeedData: true))
            _scanStore = StateObject(wrappedValue: ScanStore(storageDirectory: docsDir, useSeedData: true))
            _journalStore = StateObject(wrappedValue: JournalStore(storageDirectory: docsDir, useSeedData: true))
        } else {
            _drinkStore = StateObject(wrappedValue: DrinkStore())
            _scanStore = StateObject(wrappedValue: ScanStore())
            _journalStore = StateObject(wrappedValue: JournalStore())
        }

        print("🍺 SipCheck app launched successfully!")
        if args.contains("--mock-ai") { print("🧪 Mock AI mode enabled") }
        if args.contains("--seed-data") { print("🧪 Seed data mode enabled") }
        if args.contains("--isolated-storage") { print("🧪 Isolated storage mode enabled") }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environmentObject(drinkStore)
                    .environmentObject(scanStore)
                    .environmentObject(journalStore)
            } else {
                OnboardingView()
                    .environmentObject(drinkStore)
                    .environmentObject(scanStore)
                    .environmentObject(journalStore)
            }
        }
    }
}
