import SwiftUI
import UserNotifications

@main
struct SipCheckApp: App {
    @StateObject private var drinkStore: DrinkStore
    @StateObject private var scanStore: ScanStore
    @StateObject private var journalStore: JournalStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasConfirmedAge") private var hasConfirmedAge = false

    /// Shared notification service — also acts as UNUserNotificationCenterDelegate
    @StateObject private var notificationService = NotificationService.shared

    init() {
        let args = ProcessInfo.processInfo.arguments

        // --mock-ai: All AI service calls return fixed responses (no network)
        // useMockResponses is only assignable in Debug builds
        #if DEBUG
        if args.contains("--mock-ai") {
            OpenAIService.useMockResponses = true
        }
        #endif

        // --isolated-storage: Use temp directory instead of Documents
        // --seed-data: Load known test drinks on launch
        let useIsolatedStorage = args.contains("--isolated-storage")
        let useSeedData = args.contains("--seed-data")

        // Skip age gate and onboarding in isolated-storage test mode
        if useIsolatedStorage {
            UserDefaults.standard.set(true, forKey: "hasConfirmedAge")
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
                // The design system is dark-only (fixed hex colors); without
                // this, system-styled surfaces (sheets, alerts) render light.
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - RootView (handles notification-triggered FollowUpView + CloudKit launch sync)

private struct RootView: View {
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var drinkStore: DrinkStore
    @EnvironmentObject private var journalStore: JournalStore
    @EnvironmentObject private var notificationService: NotificationService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasConfirmedAge") private var hasConfirmedAge = false

    @State private var followUpScan: Scan?
    @State private var addBeerPrefill: AddBeerPrefill?
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastSyncAttempt: Date?

    var body: some View {
        Group {
            if !hasConfirmedAge {
                AgeGateView()
            } else if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        // Launch sync fires once; if it failed (offline launch, e.g. inside a
        // store), nothing retried for the rest of the session and offline
        // saves stayed local. Re-sync on foreground, throttled.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if let last = lastSyncAttempt, Date().timeIntervalSince(last) < 300 { return }
            Task { await performLaunchSync() }
        }
        .task {
            #if DEBUG
            await runDeviceSmokeTestIfRequested()
            #endif
            await performLaunchSync()
        }
        // item-driven, not isPresented + if-let: the same two-state race that
        // blanked the Journal's want-to-try sheet applies here.
        .sheet(item: $followUpScan) { scan in
            FollowUpView(
                scan: scan,
                onTried: { prefill in
                    followUpScan = nil
                    // Momentary gap lets the follow-up sheet finish dismissing
                    // before the add-beer sheet presents (same-transaction
                    // dismiss+present drops the second sheet).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        addBeerPrefill = prefill
                    }
                },
                onNotYet: {
                    followUpScan = nil
                },
                onNotGoing: {
                    followUpScan = nil
                    var updated = scan
                    updated.wantToTry = false
                    scanStore.updateScan(updated)
                }
            )
        }
        .sheet(item: $addBeerPrefill) { prefill in
            AddBeerView(prefill: prefill)
                .environmentObject(drinkStore)
                .environmentObject(journalStore)
                .environmentObject(scanStore)
        }
        .onChange(of: notificationService.pendingFollowUpScanID) { _, scanID in
            guard let scanID = scanID else { return }
            // Only show FollowUpView for plain taps (or when no action yet).
            // Quick-action responses (.lovedIt/.meh/.skippedIt) are handled
            // entirely by the pendingFollowUpAction handler below.
            let actionResponse = notificationService.pendingFollowUpAction?.response
            guard actionResponse == nil || actionResponse == .tapped else {
                notificationService.pendingFollowUpScanID = nil
                return
            }
            // Find the scan in the store; setting the item presents the sheet.
            if let scan = scanStore.scans.first(where: { $0.id == scanID }) {
                followUpScan = scan
            } else {
                // The scan is gone (deleted here or on another device before
                // the tombstone-cancel existed). Remove the orphaned pending
                // notification instead of silently swallowing the tap forever.
                notificationService.cancelFollowUp(forScanID: scanID)
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

            case .lovedIt, .meh:
                guard let scan = scanStore.scans.first(where: { $0.id == action.scanID }) else { return }
                // Notification actions can be delivered more than once across
                // process restarts. A linked scan is already logged; keep the
                // handler idempotent instead of adding duplicate history.
                if let linkedJournalId = scan.linkedJournalId {
                    scanStore.markTried(
                        beerName: scan.beerName,
                        linkedJournalId: linkedJournalId,
                        sourceScanId: scan.id
                    )
                    notificationService.pendingFollowUpScanID = nil
                    return
                }
                let isLoved = action.response == .lovedIt
                let rating: Rating = isLoved ? .like : .neutral
                let drink = Drink(
                    name: scan.beerName,
                    brand: scan.brand ?? "",
                    style: scan.style ?? "Other",
                    rating: rating,
                    photoFileName: scan.photoFileName,
                    abv: scan.abv
                )
                drinkStore.addDrink(drink)
                // Also create a JournalEntry so it appears in the Journal tab
                let journalEntry = JournalEntry(
                    beerName: scan.beerName,
                    brand: scan.brand ?? "",
                    style: scan.style ?? "",
                    abv: scan.abv,
                    rating: isLoved ? 5 : 3,
                    photoFileName: scan.photoFileName,
                    linkedScanId: scan.id
                )
                journalStore.addEntry(journalEntry)
                scanStore.markTried(
                    beerName: scan.beerName,
                    linkedJournalId: journalEntry.id,
                    sourceScanId: scan.id
                )
                // Prevent the pendingFollowUpScanID handler from also showing FollowUpView
                notificationService.pendingFollowUpScanID = nil

            case .skippedIt:
                // User didn't try the beer — just clear the want-to-try flag
                if var scan = scanStore.scans.first(where: { $0.id == action.scanID }) {
                    scan.wantToTry = false
                    scanStore.updateScan(scan)
                }
                // Prevent the pendingFollowUpScanID handler from also showing FollowUpView
                notificationService.pendingFollowUpScanID = nil
            }
        }
    }

    // MARK: - CloudKit Launch Sync

    private func performLaunchSync() async {
        lastSyncAttempt = Date()
        let result = await CloudKitSyncService.shared.fullSync(
            localDrinks: drinkStore.syncRecords,
            localScans: scanStore.syncRecords,
            localJournals: journalStore.syncRecords
        )
        // Same-actor calls (@MainActor to @MainActor) — awaiting them suspends
        // nothing and only produced compiler warnings.
        drinkStore.applyRemoteDrinks(result.drinks)
        scanStore.applyRemoteScans(result.scans)
        journalStore.applyRemoteEntries(result.journals)
    }

    #if DEBUG
    /// Physical-device verification hook. It is inert unless explicitly
    /// launched from devicectl with `--device-smoke-test` and is absent from
    /// Release/TestFlight behavior.
    private func runDeviceSmokeTestIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--device-smoke-test") else { return }
        print("DEVICE_SMOKE dataScanner supported=\(LiveScannerView.isSupported) available=\(LiveScannerView.isAvailable)")
        print("DEVICE_SMOKE foundationModels=\(OnDeviceBeerKnowledge.availabilityDescription)")
        if let result = await OnDeviceBeerKnowledge.enrich(
            text: "Guinness Draught stout",
            deviceVerdict: .yourCall
        ) {
            let name = result.name ?? "-"
            let brand = result.brand ?? "-"
            let style = result.style?.rawValue ?? "-"
            let abv = result.abv.map { String(format: "%.1f", $0) } ?? "-"
            print("DEVICE_SMOKE model name=\(name) brand=\(brand) style=\(style) abv=\(abv)")
        } else {
            print("DEVICE_SMOKE model response=nil")
        }
    }
    #endif
}
