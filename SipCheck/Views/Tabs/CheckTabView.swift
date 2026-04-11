import SwiftUI
import AVFoundation

struct CheckTabView: View {
    @EnvironmentObject var scanStore: ScanStore
    @EnvironmentObject var drinkStore: DrinkStore
    @EnvironmentObject private var journalStore: JournalStore

    // Camera / input state
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPermissionAlert = false
    @State private var showingTextEntry = false
    @State private var textEntryInput = ""

    // Scan flow state
    @State private var isScanning = false
    @State private var scanError: String?

    // Result state
    @State private var scanTask: Task<Void, Never>?
    @State private var currentScan: Scan?
    @State private var showingFollowUp = false
    @State private var showingAddBeer = false
    @State private var addBeerPrefill: AddBeerPrefill?

    // Scanning animation state
    @State private var spinnerDegrees: Double = 0
    @State private var scanningPhraseIndex = 0
    private let scanningPhrases = [
        "Judging this beer...",
        "Reading the label...",
        "Checking your taste profile...",
        "Forming an opinion..."
    ]

    // Notification service
    private let notificationService = NotificationService.shared

    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            if isScanning {
                scanningView
            } else if let scan = currentScan {
                VerdictCardView(
                    scan: scan,
                    onSaveForLater: {
                        saveForLater(scan)
                    },
                    onScanAnother: {
                        resetScanState()
                    }
                )
            } else {
                scanPromptView
            }

            if let errorMsg = scanError {
                errorBannerView(message: errorMsg)
            }
        }
        .accessibilityIdentifier("checkTab")
        .sheet(isPresented: $showingCamera) {
            CameraView(capturedImage: $capturedImage)
        }
        .sheet(isPresented: $showingTextEntry) {
            textEntrySheet
        }
        .sheet(isPresented: $showingFollowUp) {
            if let scan = currentScan ?? scanStore.scans.first {
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
                        if let scan = currentScan ?? scanStore.scans.first {
                            var updated = scan
                            updated.wantToTry = false
                            scanStore.updateScan(updated)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddBeer) {
            if let prefill = addBeerPrefill {
                AddBeerView(prefill: prefill)
                    .environmentObject(drinkStore)
                    .environmentObject(journalStore)
            } else {
                AddBeerView()
                    .environmentObject(drinkStore)
                    .environmentObject(journalStore)
            }
        }
        .alert("Camera Access Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable camera access in Settings to scan beer labels.")
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                runScan(image: image)
            }
        }
    }

    // MARK: - Scan Prompt (Empty State)

    private var scanPromptView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(SipColors.textSecondary)

            VStack(spacing: 8) {
                Text("What Are You Drinking?")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)

                Text("Snap a label. We'll tell you if it's worth your money.")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                requestCameraAndScan()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text("Scan Label")
                }
                .font(SipTypography.headline)
                .foregroundColor(SipColors.background)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SipColors.primary)
                )
            }
            .accessibilityIdentifier("scanNowButton")

            Button(action: {
                showingTextEntry = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                    Text("Enter beer name")
                }
                .font(SipTypography.subhead)
                .foregroundColor(SipColors.primary)
            }
            .accessibilityIdentifier("enterTextButton")
        }
    }

    // MARK: - Scanning Progress View

    private var scanningView: some View {
        VStack(spacing: 28) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(SipColors.primary.opacity(0.2), lineWidth: 4)
                    .frame(width: 72, height: 72)
                // Spinning arc
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        SipColors.primary,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(spinnerDegrees))
                // Beer icon center
                Image(systemName: "mug.fill")
                    .font(.system(size: 24))
                    .foregroundColor(SipColors.primary)
            }
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    spinnerDegrees = 360
                }
                startPhraseCycling()
            }

            Text(scanningPhrases[scanningPhraseIndex])
                .font(SipTypography.body)
                .foregroundColor(SipColors.textSecondary)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .id(scanningPhraseIndex)
                .animation(.easeInOut(duration: 0.3), value: scanningPhraseIndex)
        }
    }

    private func startPhraseCycling() {
        Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { timer in
            guard isScanning else {
                timer.invalidate()
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                scanningPhraseIndex = (scanningPhraseIndex + 1) % scanningPhrases.count
            }
        }
    }

    // MARK: - Error Banner

    private func errorBannerView(message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textPrimary)
                Spacer()
                Button {
                    scanError = nil
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(SipColors.textSecondary)
                }
            }
            .padding()
            .background(SipColors.surface)
            .cornerRadius(12)
            .padding()
        }
    }

    // MARK: - Text Entry Sheet

    private var textEntrySheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter beer name or description")
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                    TextField("e.g. Lagunitas IPA, hoppy pale ale...", text: $textEntryInput)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("beerTextInput")
                }
                .padding(.horizontal)

                Button(action: {
                    showingTextEntry = false
                    let input = textEntryInput
                    textEntryInput = ""
                    runScan(text: input)
                }) {
                    Text("Check This Beer")
                        .font(SipTypography.headline)
                        .foregroundColor(SipColors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(textEntryInput.trimmingCharacters(in: .whitespaces).isEmpty ? SipColors.textSecondary : SipColors.primary)
                        )
                }
                .padding(.horizontal)
                .disabled(textEntryInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("checkBeerButton")

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Enter Beer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        textEntryInput = ""
                        showingTextEntry = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func requestCameraAndScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            capturedImage = nil
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        capturedImage = nil
                        showingCamera = true
                    }
                }
            }
        case .denied, .restricted:
            showingPermissionAlert = true
        @unknown default:
            break
        }
    }

    private func runScan(image: UIImage) {
        guard !isScanning else { return }
        isScanning = true
        scanError = nil
        currentScan = nil

        scanTask = Task {
            do {
                let result = try await ScanningPipeline.shared.scan(image: image)
                let scan = buildScan(from: result)
                await MainActor.run {
                    finalizeScan(scan)
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    scanError = "Scan failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func runScan(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !isScanning else { return }

        isScanning = true
        scanError = nil
        currentScan = nil

        scanTask = Task {
            do {
                let result = try await ScanningPipeline.shared.scan(text: trimmed)
                let scan = buildScan(from: result)
                await MainActor.run {
                    finalizeScan(scan)
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    scanError = "Scan failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func buildScan(from result: ScanResult) -> Scan {
        Scan(
            beerName: result.beerInfo.name ?? "Unknown Beer",
            style: result.beerInfo.style?.rawValue,
            abv: result.beerInfo.abv,
            verdict: result.verdict,
            explanation: result.explanation,
            wantToTry: false,
            origin: result.beerInfo.origin
        )
    }

    private func finalizeScan(_ scan: Scan) {
        scanStore.addScan(scan)
        notificationService.scheduleFollowUp(for: scan)
        currentScan = scan
        isScanning = false
    }

    private func saveForLater(_ scan: Scan) {
        var updated = scan
        updated.wantToTry = true
        scanStore.updateScan(updated)
        notificationService.scheduleFollowUp(for: updated)
    }

    private func resetScanState() {
        scanTask?.cancel()
        scanTask = nil
        currentScan = nil
        capturedImage = nil
        scanError = nil
        spinnerDegrees = 0
        scanningPhraseIndex = 0
    }
}

struct CheckTabView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // With seed data
            CheckTabView()
                .environmentObject(
                    ScanStore(
                        storageDirectory: FileManager.default.temporaryDirectory,
                        useSeedData: true
                    )
                )
                .environmentObject(DrinkStore())
                .previewDisplayName("With Scan Result")

            // Empty state
            CheckTabView()
                .environmentObject(
                    ScanStore(
                        storageDirectory: FileManager.default.temporaryDirectory,
                        useSeedData: false
                    )
                )
                .environmentObject(DrinkStore())
                .previewDisplayName("Empty State")
        }
    }
}
