import SwiftUI
import AVFoundation

struct CheckTabView: View {
    @EnvironmentObject var scanStore: ScanStore
    @EnvironmentObject var drinkStore: DrinkStore

    /// The scan flow's single source of truth (SPEED_PLAN §2).
    ///
    /// Legal transitions: idle → recognizing → verdict(refining: true|false),
    /// and verdict(refining: true) → verdict(refining: false). The network can
    /// never move the machine backwards — a refinement failure just flips
    /// `refining` off and the on-device verdict stands. `.failed` is reachable
    /// only from `.recognizing` (nothing readable in frame), never from
    /// refinement.
    private enum ScanPhase: Equatable {
        case idle
        case recognizing
        case verdict(Scan, refining: Bool)
        case failed(String)
    }

    /// Everything the on-device stage decides — computed off the main actor.
    private struct ScanOutcome {
        let scan: Scan
        /// Resolver source ("labelText"/"catalog"/"unresolved") or "menu".
        let source: String
        let score: Double
        /// True when the shown name is a best-guess that network refinement
        /// is allowed to replace.
        let nameIsGuess: Bool
        /// True when the scan had no style signal on-device — refinement must
        /// then keep facts and copy moving together (no "IPA · 6.5%" above
        /// "couldn't tell the style").
        let startedStyleless: Bool
        /// Menu scans are on-device-final: enriching the winner against the
        /// whole menu blob would only re-extract the wrong beer.
        let isMenu: Bool
    }

    // Camera / input state
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPermissionAlert = false
    @State private var showingTextEntry = false
    @State private var textEntryInput = ""
    @FocusState private var textEntryFocused: Bool

    // Scan flow state
    @State private var phase: ScanPhase = .idle
    @State private var savedForLater = false
    /// Monotonic guard so a stale OCR task can never deliver into a newer scan.
    @State private var scanGeneration = 0
    @State private var scanTask: Task<Void, Never>?
    @State private var refineTask: Task<Void, Never>?


    // Scanning animation state
    @State private var spinnerDegrees: Double = 0
    @State private var scanningPhraseIndex = 0
    @State private var phraseTimer: Timer?
    private let scanningPhrases = [
        "Judging this beer...",
        "Reading the label...",
        "Checking your taste profile...",
        "Forming an opinion..."
    ]

    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            switch phase {
            case .idle:
                scanPromptView
            case .recognizing:
                scanningView
            case .verdict(let scan, let refining):
                VerdictCardView(
                    scan: scan,
                    // Exact-name match only: a fuzzy hit here would put a false
                    // "you've had this one" banner on a beer the user never tried.
                    previousDrink: BeerMatcher.exactMatch(for: scan.beerName, in: drinkStore.drinks),
                    refining: refining,
                    savedForLater: savedForLater,
                    onSaveForLater: {
                        saveForLater(scan)
                    },
                    onScanAnother: {
                        resetScanState()
                    }
                )
            case .failed(let message):
                scanPromptView
                errorBannerView(message: message)
            }
        }
        // .contain keeps this container id from clobbering every child's
        // identifier (E2E_FINDINGS.md F12 — matches journalTab/profileTab).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkTab")
        // Verdict lands: a felt cue before it's read. Confidence-gated — the
        // celebratory tap is reserved for TRY IT; others get a neutral bump.
        .sensoryFeedback(trigger: verdictStamp) { _, newValue in
            guard let newValue else { return nil }
            return newValue.hasSuffix(Verdict.tryIt.rawValue) ? .success : .impact(weight: .medium)
        }
        .sensoryFeedback(trigger: savedForLater) { _, newValue in
            newValue ? .selection : nil
        }
        .task {
            // Warm the catalog decode + token indexes off the main actor so
            // scan #1 pays the same ~0ms lookup cost as scan #10.
            Task.detached(priority: .utility) { _ = BundledCatalog.shared }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(capturedImage: $capturedImage)
        }
        .sheet(isPresented: $showingTextEntry) {
            textEntrySheet
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

    // MARK: - Derived State

    private var currentScan: Scan? {
        if case .verdict(let scan, _) = phase { return scan }
        return nil
    }

    /// Changes exactly once per delivered verdict (id + verdict), stable across
    /// refinement patches — drives the verdict haptic.
    private var verdictStamp: String? {
        if case .verdict(let scan, _) = phase { return "\(scan.id.uuidString)-\(scan.verdict.rawValue)" }
        return nil
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
        // Invalidate-and-replace so repeated recognizing phases can't stack timers.
        phraseTimer?.invalidate()
        phraseTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { timer in
            guard case .recognizing = phase else {
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
                    phase = .idle
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
                        .focused($textEntryFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            submitTextEntry()
                        }
                        .accessibilityIdentifier("beerTextInput")
                }
                .padding(.horizontal)

                Button(action: {
                    submitTextEntry()
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
            .onAppear {
                // Focusing during the sheet's presentation animation silently
                // fails (verified on-simulator: keyboard never rose). Delay
                // until the sheet has settled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    textEntryFocused = true
                }
            }
        }
    }

    private func submitTextEntry() {
        let input = textEntryInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        showingTextEntry = false
        textEntryInput = ""
        runScan(text: input)
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
                    } else {
                        showingPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingPermissionAlert = true
        @unknown default:
            break
        }
    }

    // MARK: - Verdict-First Scan Flow (SPEED_PLAN §2)
    //
    // Stage 1 (on-device, sub-second): OCR → menu detection → resolver (printed
    // style/ABV + bundled catalog) → TasteScorer → verdict on screen. All the
    // pure compute (catalog decode, scoring) runs OFF the main actor.
    // Stage 2 (network, optional): a single bounded enrichment call that only
    // fills blanks and upgrades copy — never the verdict, never the phase.

    private func runScan(image: UIImage) {
        guard startScan() else { return }
        let generation = scanGeneration
        let drinks = drinkStore.drinks

        scanTask = Task(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let ocrResult = await VisionOCRService.extractText(from: image)
            let text = ocrResult.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                // Nothing readable in frame (glare, glossy can). An honest
                // retake prompt beats a garbage verdict built from nothing.
                await MainActor.run {
                    guard generation == scanGeneration, case .recognizing = phase else { return }
                    phase = .failed("Couldn't read the label — try again with less glare, or type the name.")
                }
                return
            }

            let outcome = Self.computeOutcome(fromText: text, path: "image", drinks: drinks)
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

            await MainActor.run {
                guard generation == scanGeneration, case .recognizing = phase else { return }
                present(outcome, rawText: text, path: "image", latencyMs: latencyMs, image: image)
            }
        }
    }

    private func runScan(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard startScan() else { return }
        let generation = scanGeneration
        let drinks = drinkStore.drinks

        scanTask = Task(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let outcome = Self.computeOutcome(fromText: trimmed, path: "text", drinks: drinks)
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

            await MainActor.run {
                guard generation == scanGeneration, case .recognizing = phase else { return }
                present(outcome, rawText: trimmed, path: "text", latencyMs: latencyMs, image: nil)
            }
        }
    }

    /// Common scan entry: cancels stale work, resets per-scan UI state, and
    /// moves the machine to `.recognizing`. Returns false when a scan is
    /// already being recognized (double-tap guard).
    private func startScan() -> Bool {
        if case .recognizing = phase { return false }
        scanTask?.cancel()
        refineTask?.cancel()
        scanGeneration += 1
        savedForLater = false
        spinnerDegrees = 0
        scanningPhraseIndex = 0
        withAnimation { phase = .recognizing }
        return true
    }

    /// Stage 1 compute — pure and static so it can run off the main actor.
    private static func computeOutcome(fromText text: String, path: String, drinks: [Drink]) -> ScanOutcome {
        let profile = TasteProfile.build(from: drinks)
        let prefs = TastePreferences.current

        // Menu detection first (locked constraint: menu → ONE clear winner).
        // Two-plus parsed candidates means this is a list, not a label.
        let menuCandidates = MenuParser.parse(text)
        if menuCandidates.count >= 2,
           let winner = MenuParser.evaluate(candidates: menuCandidates, profile: profile, preferences: prefs).winner {
            let scan = Scan(
                beerName: winner.name,
                style: winner.style?.rawValue,
                abv: winner.abv,
                verdict: winner.assessment.verdict,
                explanation: menuExplanation(winner: winner, totalCandidates: menuCandidates.count),
                wantToTry: false,
                origin: nil
            )
            return ScanOutcome(
                scan: scan,
                source: "menu",
                score: winner.assessment.score,
                nameIsGuess: false,
                startedStyleless: winner.style == nil,
                isMenu: true
            )
        }

        // Single-beer path: fuse printed style/ABV with a bundled-catalog match.
        let resolved = BeerResolver.resolve(recognizedText: text, using: BundledCatalog.shared)
        let assessment = TasteScorer.assess(
            name: resolved.name,
            style: resolved.style,
            abv: resolved.abv,
            profile: profile,
            preferences: prefs
        )
        let (name, nameIsGuess) = displayName(fromText: text, resolved: resolved, path: path)

        let scan = Scan(
            beerName: name,
            style: resolved.style?.rawValue,
            abv: resolved.abv,
            verdict: assessment.verdict,
            explanation: sentenceCase(assessment.shortReason),
            wantToTry: false,
            origin: nil
        )
        return ScanOutcome(
            scan: scan,
            source: resolved.source.rawValue,
            score: assessment.score,
            nameIsGuess: nameIsGuess,
            startedStyleless: resolved.style == nil,
            isMenu: false
        )
    }

    private static func menuExplanation(winner: TasteScorer.AssessedCandidate, totalCandidates: Int) -> String {
        let reason = sentenceCase(winner.assessment.shortReason)
        switch winner.assessment.verdict {
        case .tryIt:
            return "Order this — the best of the \(totalCandidates) beers we read on this menu. \(reason)"
        case .yourCall:
            return "Closest match of the \(totalCandidates) beers we read on this menu. \(reason)"
        case .skipIt:
            return "Slim pickings — of the \(totalCandidates) beers we read, this is nearest your taste. \(reason)"
        }
    }

    /// Stage 1 presentation — main actor: log, persist, show, kick refinement.
    private func present(_ outcome: ScanOutcome, rawText: String, path: String, latencyMs: Int, image: UIImage?) {
        ScanLog.shared.record(
            ScanEvent(
                timestamp: Date(),
                inputText: String(rawText.prefix(200)),
                resolvedName: outcome.scan.beerName,
                style: outcome.scan.style,
                abv: outcome.scan.abv,
                source: outcome.source,
                verdict: outcome.scan.verdict.rawValue,
                score: outcome.score,
                latencyMs: latencyMs,
                path: path
            )
        )

        scanStore.addScan(outcome.scan)
        // Follow-up notifications are earned by Save for Later, not by merely
        // looking: browsing eight beers in an aisle must not queue eight
        // "Did you try X?" pushes for beers the user walked past.

        savedForLater = false
        let willRefine = !outcome.isMenu && ScanningPipeline.shared.canEnrich
        withAnimation { phase = .verdict(outcome.scan, refining: willRefine) }
        if willRefine {
            startRefinement(for: outcome.scan, text: rawText, outcome: outcome, image: image)
        }
    }

    /// Stage 2: bounded background enrichment. Patches blanks and upgrades the
    /// explanation copy in place; the verdict and the phase kind never change.
    private func startRefinement(for scan: Scan, text: String, outcome: ScanOutcome, image: UIImage?) {
        let nameIsGuess = outcome.nameIsGuess
        let startedStyleless = outcome.startedStyleless

        refineTask = Task(priority: .utility) {
            // Weak or guessed reads get the frame too, so a graphic label with
            // garbage OCR can still be identified by the vision fallback.
            let sendImage = (nameIsGuess || text.count < 15) ? image : nil
            let enrichment = await ScanningPipeline.shared.enrich(
                text: text,
                image: sendImage,
                deviceVerdict: scan.verdict
            )
            if Task.isCancelled { return }

            await MainActor.run {
                // Only patch the scan that's still on screen.
                guard case .verdict(var current, _) = phase, current.id == scan.id else { return }
                if let e = enrichment {
                    var nameChanged = false
                    if nameIsGuess, let name = e.name, name != current.beerName {
                        current.beerName = name
                        nameChanged = true
                    }
                    // Facts and copy move together: never render "IPA · 6.5%"
                    // above copy that still says "couldn't tell the style".
                    let canPatchFacts = !startedStyleless || e.explanation != nil
                    if canPatchFacts, current.style == nil, let style = e.style { current.style = style.rawValue }
                    if canPatchFacts, current.abv == nil, let abv = e.abv { current.abv = abv }
                    if current.origin == nil, let origin = e.origin { current.origin = origin }
                    if let explanation = e.explanation { current.explanation = explanation }
                    scanStore.updateScan(current)
                    if nameChanged, current.wantToTry {
                        // Same identifier → replaces the pending follow-up, so the
                        // notification names the corrected beer. Only saved beers
                        // have a follow-up pending to correct.
                        NotificationService.shared.scheduleFollowUpIfAuthorized(for: current)
                    }
                }
                withAnimation(.easeInOut(duration: 0.35)) {
                    phase = .verdict(current, refining: false)
                }
            }
        }
    }

    /// Choose what to show as the beer's name, and whether it's a guess that
    /// network refinement is allowed to replace. Trust is graded by catalog
    /// confidence — a 0.6 fuzzy hit must not permanently rename the scan.
    private static func displayName(fromText text: String, resolved: ResolvedBeer, path: String) -> (name: String, isGuess: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let confidence = resolved.confidence {
            // High-confidence catalog hit: canonical name is authoritative.
            if confidence >= 0.9 { return (resolved.name, false) }
            // Moderate hit: show the canonical name, but refinement may correct it.
            return (resolved.name, true)
        }

        // No catalog hit. Typed input is the user's own words — trust it.
        // A single-line OCR read is still machine output, so it stays replaceable.
        if !trimmed.contains("\n") {
            return (String(trimmed.prefix(60)), path == "image")
        }

        // Multi-line OCR blob (that didn't parse as a menu): best-guess the
        // first non-empty line and let refinement supply the real name.
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? trimmed
        return (String(firstLine.prefix(60)), true)
    }

    /// "matches your love of IPA" → "Matches your love of IPA."
    private static func sentenceCase(_ fragment: String) -> String {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        let capitalized = first.uppercased() + trimmed.dropFirst()
        return capitalized.hasSuffix(".") || capitalized.hasSuffix("!") ? capitalized : capitalized + "."
    }

    private func saveForLater(_ scan: Scan) {
        guard !savedForLater else { return }
        var updated = scan
        updated.wantToTry = true
        scanStore.updateScan(updated)
        // E2E handoff F5: this is the moment that earns the notification ask.
        NotificationService.shared.requestAuthorizationAndScheduleFollowUp(for: updated)
        savedForLater = true
        // Keep the phase's scan in sync so a late refinement patch can't
        // clobber wantToTry with the stale pre-save copy.
        if case .verdict(_, let refining) = phase {
            phase = .verdict(updated, refining: refining)
        }
    }

    private func resetScanState() {
        scanTask?.cancel()
        scanTask = nil
        refineTask?.cancel()
        refineTask = nil
        phraseTimer?.invalidate()
        phraseTimer = nil
        scanGeneration += 1
        savedForLater = false
        capturedImage = nil
        spinnerDegrees = 0
        scanningPhraseIndex = 0
        withAnimation { phase = .idle }
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
