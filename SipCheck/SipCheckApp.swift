import SwiftUI
import UserNotifications

@main
struct SipCheckApp: App {
    @StateObject private var drinkStore: DrinkStore
    @StateObject private var scanStore: ScanStore
    @StateObject private var journalStore: JournalStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Shared notification service — also acts as UNUserNotificationCenterDelegate
    @StateObject private var notificationService = NotificationService.shared

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

        print("SipCheck app launched successfully!")
        if args.contains("--mock-ai") { print("Mock AI mode enabled") }
        if args.contains("--seed-data") { print("Seed data mode enabled") }
        if args.contains("--isolated-storage") { print("Isolated storage mode enabled") }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(drinkStore)
                .environmentObject(scanStore)
                .environmentObject(journalStore)
                .environmentObject(notificationService)
        }
    }
}

// MARK: - RootView (handles notification-triggered FollowUpView)

private struct RootView: View {
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var drinkStore: DrinkStore
    @EnvironmentObject private var notificationService: NotificationService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var followUpScan: Scan?
    @State private var showingFollowUp = false
    @State private var showingAddBeer = false
    @State private var addBeerPrefill: AddBeerPrefill?

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .sheet(isPresented: $showingFollowUp) {
            if let scan = followUpScan {
                FollowUpView(
                    scan: scan,
                    onTried: { prefill in
                        showingFollowUp = false
                        addBeerPrefill = prefill
                        showingAddBeer = true
                    },
                    onNotYet: {
                        showingFollowUp = false
                    },
                    onNotGoing: {
                        showingFollowUp = false
                        var updated = scan
                        updated.wantToTry = false
                        scanStore.updateScan(updated)
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddBeer) {
            if let prefill = addBeerPrefill {
                AddBeerView(prefill: prefill)
                    .environmentObject(drinkStore)
            } else {
                AddBeerView()
                    .environmentObject(drinkStore)
            }
        }
        .onChange(of: notificationService.pendingFollowUpScanID) { _, scanID in
            guard let scanID = scanID else { return }
            // Find the scan in the store
            if let scan = scanStore.scans.first(where: { $0.id == scanID }) {
                followUpScan = scan
                showingFollowUp = true
            }
            // Clear the pending ID
            notificationService.pendingFollowUpScanID = nil
        }
        .onChange(of: notificationService.pendingFollowUpAction) { _, action in
            guard let action = action else { return }
            defer { notificationService.pendingFollowUpAction = nil }

            switch action.response {
            case .tapped:
                // Plain tap — show FollowUpView (same as legacy pendingFollowUpScanID path)
                // pendingFollowUpScanID is already set by the delegate, so FollowUpView
                // will be triggered by the sibling onChange above. Nothing extra needed.
                break

            case .lovedIt, .meh, .skippedIt:
                guard let scan = scanStore.scans.first(where: { $0.id == action.scanID }) else { return }
                let rating: Rating
                switch action.response {
                case .lovedIt:   rating = .like
                case .meh:       rating = .neutral
                case .skippedIt: rating = .dislike
                default:         rating = .neutral
                }
                let drink = Drink(
                    name: scan.beerName,
                    style: scan.style ?? "Other",
                    rating: rating,
                    abv: scan.abv
                )
                drinkStore.addDrink(drink)
            }
        }
    }
}
