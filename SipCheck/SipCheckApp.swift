import SwiftUI
import UIKit
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
                // Keep every control legible at the system's two largest text
                // settings. Accessibility XL remains fully supported; above
                // it, fixed-format scan/onboarding controls otherwise collapse
                // into ambiguous ellipses on compact phones.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
            if phase == .background {
                drinkStore.flushPersistence()
                scanStore.flushPersistence()
                journalStore.flushPersistence()
                return
            }
            guard phase == .active else { return }
            if let last = lastSyncAttempt, Date().timeIntervalSince(last) < 300 { return }
            Task { await performLaunchSync() }
        }
        .task {
            #if DEBUG
            await runDeviceSmokeTestIfRequested()
            await runDeviceImageBatchTestIfRequested()
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

    private struct DeviceImageBatchResult: Encodable {
        let file: String
        let ocrText: String
        let ocrConfidence: Float
        let localName: String
        let localBrand: String?
        let localStyle: String?
        let localABV: Double?
        let localSource: String
        let catalogConfidence: Double?
        let modelName: String?
        let modelBrand: String?
        let modelStyle: String?
        let modelABV: Double?
        let modelOrigin: String?
        let onlineName: String?
        let onlineBrand: String?
        let onlineStyle: String?
        let onlineOrigin: String?
        let finalName: String
        let finalStyle: String?
        let elapsedMs: Int
        let error: String?
    }

    /// Runs the real Vision + offline resolver stack over images copied into
    /// Documents/ValidationSamples. Foundation Models may refine uncertain
    /// names. Paid vision runs only when the explicit
    /// `--device-image-batch-online` development flag is also present.
    private func runDeviceImageBatchTestIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--device-image-batch-test") else { return }
        let includeOnlineVision = ProcessInfo.processInfo.arguments.contains("--device-image-batch-online")
        let includeOnDeviceModel = ProcessInfo.processInfo.arguments.contains("--device-image-batch-model")

        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("DEVICE_BATCH error=documents-unavailable")
            return
        }
        let samplesDirectory = documents.appendingPathComponent("ValidationSamples", isDirectory: true)
        do {
            try fileManager.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)
        } catch {
            print("DEVICE_BATCH error=samples-directory-unavailable description=\(error)")
            return
        }
        let allowedExtensions = Set(["heic", "jpeg", "jpg", "png"])
        let directorySampleURLs = ((try? fileManager.contentsOfDirectory(
            at: samplesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        // Never fall back to arbitrary Documents images: online mode must only
        // upload the deliberately prepared validation corpus.
        let sampleURLs = directorySampleURLs
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !sampleURLs.isEmpty else {
            print("DEVICE_BATCH error=no-images path=\(samplesDirectory.path)")
            return
        }

        print("DEVICE_BATCH start count=\(sampleURLs.count) paidAPIs=\(includeOnlineVision)")
        var results: [DeviceImageBatchResult] = []
        results.reserveCapacity(sampleURLs.count)

        for (index, url) in sampleURLs.enumerated() {
            let startedAt = Date()
            guard let image = UIImage(contentsOfFile: url.path) else {
                results.append(
                    DeviceImageBatchResult(
                        file: url.lastPathComponent,
                        ocrText: "",
                        ocrConfidence: 0,
                        localName: "",
                        localBrand: nil,
                        localStyle: nil,
                        localABV: nil,
                        localSource: ResolvedBeer.Source.unresolved.rawValue,
                        catalogConfidence: nil,
                        modelName: nil,
                        modelBrand: nil,
                        modelStyle: nil,
                        modelABV: nil,
                        modelOrigin: nil,
                        onlineName: nil,
                        onlineBrand: nil,
                        onlineStyle: nil,
                        onlineOrigin: nil,
                        finalName: "",
                        finalStyle: nil,
                        elapsedMs: 0,
                        error: "image-load-failed"
                    )
                )
                continue
            }

            let ocr = await VisionOCRService.extractText(from: image)
            let resolved = BeerResolver.resolve(recognizedText: ocr.text, using: BundledCatalog.shared)
            let shouldUseModel = resolved.style == nil
            let model = shouldUseModel && includeOnDeviceModel && !includeOnlineVision
                ? await OnDeviceBeerKnowledge.enrich(
                    text: ocr.text,
                    candidateName: resolved.name,
                    deviceVerdict: .yourCall
                )
                : nil
            let online: OpenAIService.BeerExtractionResult?
            if includeOnlineVision {
                do {
                    online = try await OpenAIService.shared.extractBeerInfo(
                        from: image,
                        ocrText: ocr.text,
                        candidateName: resolved.name
                    )
                } catch {
                    online = nil
                    print("DEVICE_BATCH online-error file=\(url.lastPathComponent) description=\(error.localizedDescription)")
                }
            } else {
                online = nil
            }
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let finalName = online?.name ?? model?.name ?? resolved.name
            let finalStyle = online?.style ?? model?.style ?? resolved.style

            results.append(
                DeviceImageBatchResult(
                    file: url.lastPathComponent,
                    ocrText: ocr.text,
                    ocrConfidence: ocr.confidence,
                    localName: resolved.name,
                    localBrand: resolved.brewery,
                    localStyle: resolved.style?.rawValue,
                    localABV: resolved.abv,
                    localSource: resolved.source.rawValue,
                    catalogConfidence: resolved.confidence,
                    modelName: model?.name,
                    modelBrand: model?.brand,
                    modelStyle: model?.style?.rawValue,
                    modelABV: model?.abv,
                    modelOrigin: model?.origin,
                    onlineName: online?.name,
                    onlineBrand: online?.brand,
                    onlineStyle: online?.style?.rawValue,
                    onlineOrigin: online?.origin,
                    finalName: finalName,
                    finalStyle: finalStyle?.rawValue,
                    elapsedMs: elapsedMs,
                    error: nil
                )
            )
            let confidenceText = String(format: "%.2f", ocr.confidence)
            let modelName = model?.name ?? "-"
            let onlineName = online?.name ?? "-"
            let styleName = finalStyle?.rawValue ?? "-"
            print(
                "DEVICE_BATCH item=\(index + 1)/\(sampleURLs.count) file=\(url.lastPathComponent) "
                    + "ocr=\(confidenceText) local=\(resolved.name) "
                    + "model=\(modelName) online=\(onlineName) final=\(finalName) style=\(styleName) "
                    + "ms=\(elapsedMs)"
            )
        }

        let reportName = includeOnlineVision
            ? "device-image-batch-results-online.json"
            : "device-image-batch-results.json"
        let reportURL = documents.appendingPathComponent(reportName)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: reportURL, options: .atomic)
            print("DEVICE_BATCH complete count=\(results.count) report=\(reportURL.path)")
        } catch {
            print("DEVICE_BATCH error=report-write-failed description=\(error)")
        }
    }
    #endif
}
