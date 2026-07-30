import SwiftUI
import AVFoundation

/// Settles the recommendation from local evidence before anything is shown.
/// A guessed camera identity may suggest fuzzy catalog facts for enrichment,
/// but only fields independently printed in the frame may drive the first
/// personalized recommendation. Printed style remains sufficient.
enum ScanRecommendationSettlementPolicy {
    struct Recommendation: Equatable {
        let verdict: Verdict
        let explanation: String
        let score: Double
        let keepResolvedFacts: Bool
    }

    struct TrustedFacts: Equatable {
        let brewery: String?
        let style: BeerStyle?
        let abv: Double?
    }

    /// A provisional identity cannot lend its catalog fields to the first
    /// recommendation. Keep only style/ABV independently printed in the frame;
    /// typed and high-confidence identities may use the complete resolved row.
    static func trustedFacts(
        from resolved: ResolvedBeer,
        recognizedText: String,
        nameIsGuess: Bool,
        isTypedInput: Bool
    ) -> TrustedFacts {
        guard nameIsGuess, !isTypedInput else {
            return TrustedFacts(
                brewery: resolved.brewery,
                style: resolved.style,
                abv: resolved.abv
            )
        }

        guard case .labelText = resolved.source else {
            return TrustedFacts(brewery: nil, style: nil, abv: nil)
        }
        return TrustedFacts(
            brewery: nil,
            style: resolved.style,
            abv: MenuParser.extractABV(from: recognizedText)
        )
    }

    static func hasReliableStyle(
        nameIsGuess: Bool,
        resolvedStyle: BeerStyle?,
        source: ResolvedBeer.Source
    ) -> Bool {
        guard resolvedStyle != nil else { return false }
        guard nameIsGuess else { return true }

        // For a provisional identity, only style read directly in the frame is
        // independent of that identity. A fuzzy catalog style can belong to a
        // different beer and must not create a TRY/SKIP recommendation.
        if case .labelText = source { return true }
        return false
    }

    static func settleInitial(
        proposedVerdict: Verdict,
        proposedExplanation: String,
        proposedScore: Double,
        nameIsGuess: Bool,
        resolvedStyle: BeerStyle?,
        source: ResolvedBeer.Source,
        isTypedInput: Bool,
        isMenu: Bool
    ) -> Recommendation {
        let reliableStyle = hasReliableStyle(
            nameIsGuess: nameIsGuess,
            resolvedStyle: resolvedStyle,
            source: source
        )
        guard !isMenu, !isTypedInput, nameIsGuess, !reliableStyle else {
            return Recommendation(
                verdict: proposedVerdict,
                explanation: proposedExplanation,
                score: proposedScore,
                keepResolvedFacts: true
            )
        }

        return Recommendation(
            verdict: .yourCall,
            explanation: "We weren't confident enough to call this one - trust your gut.",
            score: 0,
            keepResolvedFacts: false
        )
    }

    /// A provisional camera identity may refine its metadata, but not the
    /// recommendation already shown. Non-provisional inputs can still gain a
    /// verdict once their missing facts resolve.
    static func settleRefinement(
        visibleVerdict: Verdict,
        visibleExplanation: String,
        proposedVerdict: Verdict,
        proposedExplanation: String,
        proposedScore: Double,
        freezeVisibleRecommendation: Bool
    ) -> Recommendation {
        guard freezeVisibleRecommendation else {
            return Recommendation(
                verdict: proposedVerdict,
                explanation: proposedExplanation,
                score: proposedScore,
                keepResolvedFacts: true
            )
        }
        return Recommendation(
            verdict: visibleVerdict,
            explanation: visibleExplanation,
            score: 0,
            keepResolvedFacts: true
        )
    }
}

struct CheckTabView: View {
    @EnvironmentObject var scanStore: ScanStore
    @EnvironmentObject var drinkStore: DrinkStore
    @EnvironmentObject var journalStore: JournalStore

    /// The scan flow's single source of truth (SPEED_PLAN §2).
    ///
    /// Legal transitions: idle → recognizing → verdict(refining: true|false),
    /// and verdict(refining: true) → verdict(refining: false). The network can
    /// never move the machine backwards: a refinement failure just flips
    /// `refining` off and the settled on-device recommendation stands. New
    /// facts may correct metadata, but cannot change a recommendation the user
    /// has already seen. `.failed` is reachable only from `.recognizing`.
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
        /// True when no reliable style was used for the settled recommendation.
        /// This includes identity-derived facts discarded from a fuzzy match.
        let startedStyleless: Bool
        /// Menu scans are on-device-final: enriching the winner against the
        /// whole menu blob would only re-extract the wrong beer.
        let isMenu: Bool
        /// Menu mode keeps the second-ranked choice one tap away without
        /// cluttering the immediate "Order this" answer.
        let menuRunnerUp: Scan?
    }

    private struct TextEntrySearchState {
        let suggestions: [ResolvedBeer]
        let customQuery: String?
    }

    // Camera / input state
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingLiveScanner = false
    @State private var showingPermissionAlert = false
    @State private var pendingLiveScanText: String?
    @State private var showingTextEntry = false
    @State private var textEntryInput = ""
    @State private var discoverySuggestions: [BeerDiscoveryCandidate] = []
    @State private var isDiscoveringBeers = false
    @State private var beerDiscoveryGeneration = 0
    @State private var beerDiscoveryTask: Task<Void, Never>?

    // Scan flow state
    @State private var phase: ScanPhase = .idle
    @State private var savedForLater = false
    /// Monotonic guard so a stale OCR task can never deliver into a newer scan.
    @State private var scanGeneration = 0
    @State private var scanTask: Task<Void, Never>?
    @State private var refineTask: Task<Void, Never>?
    @State private var menuRunnerUp: Scan?
    /// The entire verdict card is a snapshot of what SipCheck knew when the
    /// check ran. Freezing its exact-history evidence prevents a later Journal
    /// edit from being mixed with the persisted verdict/explanation.
    @State private var verdictHistorySnapshot: BeerTasteRecord?


    // Scanning animation state
    @State private var spinnerDegrees: Double = 0
    @State private var scanningPhraseIndex = 0
    @State private var phraseTimer: Timer?
    private let scanningPhrases = [
        "Reading the label…",
        "Checking it against your taste…",
        "Almost there…"
    ]

    // Hero glyph sizes scale with Dynamic Type (spec §1.4 — no fixed .system(size:)).
    @ScaledMetric(relativeTo: .largeTitle) private var idleGlyphSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title2) private var spinnerIconSize: CGFloat = 24

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
                    previousTaste: verdictHistorySnapshot,
                    refining: refining,
                    savedForLater: savedForLater,
                    capturedImage: capturedImage,
                    runnerUp: menuRunnerUp,
                    onSaveForLater: {
                        saveForLater(scan)
                    },
                    onScanAnother: {
                        resetScanState()
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                requestCameraAndScan()
                            }
                        }
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
            OnDeviceBeerKnowledge.prewarm()
            await VisionOCRService.warmUp()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-live-scanner") {
                showingLiveScanner = true
            }
            #endif
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(capturedImage: $capturedImage)
        }
        .fullScreenCover(isPresented: $showingLiveScanner) {
            LiveScannerView { capture in
                handleLiveCapture(capture)
            }
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
                if let liveText = pendingLiveScanText {
                    pendingLiveScanText = nil
                    runScan(recognizedText: liveText, image: image)
                } else {
                    runScan(image: image)
                }
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
        ViewThatFits(in: .vertical) {
            scanPromptContent

            ScrollView {
                scanPromptContent
                    .padding(.vertical, SipSpacing.m)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var scanPromptContent: some View {
        VStack(spacing: SipSpacing.xl) {
            // Beer-native idle affordance (crit note 15): amber mug framed by
            // viewfinder brackets — content imagery is tinted, never gray.
            // Static by design: motion is feedback, not decoration (spec §1.6).
            ZStack {
                Image(systemName: "viewfinder")
                    .font(.system(size: min(idleGlyphSize, 96), weight: .thin))
                    .foregroundStyle(StyleGradient.gradient(for: "IPA").opacity(0.45))
                Image(systemName: "mug.fill")
                    .font(.system(size: min(idleGlyphSize, 96) * 0.45))
                    .foregroundStyle(StyleGradient.gradient(for: "IPA"))
            }
            .accessibilityHidden(true)

            VStack(spacing: SipSpacing.s) {
                Text("What Are You Drinking?")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Do-not-lose copy (round-2 crit #10): this exact tagline is a
                // locked product line — never swap it for feature-speak.
                Text("Snap a label. We'll tell you if it's worth your money.")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SipSpacing.xxl)
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(action: {
                    requestCameraAndScan()
                }) {
                    HStack(spacing: SipSpacing.s) {
                        Image(systemName: "camera.fill")
                        Text("Scan Label")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .shadow(color: SipColors.accent.opacity(0.22), radius: 8, x: 0, y: 3)
                .padding(.horizontal, SipSpacing.xxl)
                .accessibilityIdentifier("scanNowButton")
            } else {
                PhotoLibraryButton(title: "Scan Label", capturedImage: $capturedImage)
                    .buttonStyle(SipPrimaryButtonStyle())
                    .padding(.horizontal, SipSpacing.xxl)
                    .accessibilityIdentifier("scanNowButton")
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                PhotoLibraryButton(title: "Choose from Library", capturedImage: $capturedImage)
                    .buttonStyle(SipSecondaryButtonStyle())
                    .padding(.horizontal, SipSpacing.xxl)
            }

            Button(action: {
                showingTextEntry = true
            }) {
                HStack(spacing: SipSpacing.s) {
                    Image(systemName: "keyboard")
                    Text("Enter beer name")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(SipQuietButtonStyle())
            .accessibilityIdentifier("enterTextButton")
        }
    }

    // MARK: - Scanning Progress View

    private var scanningView: some View {
        VStack(spacing: SipSpacing.xl) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(SipColors.accent.opacity(0.2), lineWidth: 4)
                    .frame(width: 72, height: 72)
                // Spinning arc — progress feedback, the one moving element here
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        SipColors.accent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(spinnerDegrees))
                // Beer icon center — same amber motif as the idle state
                Image(systemName: "mug.fill")
                    .font(.system(size: spinnerIconSize))
                    .foregroundStyle(StyleGradient.gradient(for: "IPA"))
            }
            .accessibilityHidden(true)
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
                .animation(.smooth(duration: 0.3), value: scanningPhraseIndex)
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
            withAnimation(.smooth(duration: 0.3)) {
                scanningPhraseIndex = (scanningPhraseIndex + 1) % scanningPhrases.count
            }
        }
    }

    // MARK: - Error Banner

    private func errorBannerView(message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: SipSpacing.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(SipColors.warning)
                Text(message)
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textPrimary)
                Spacer()
                Button {
                    phase = .idle
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(SipColors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.vertical, SipSpacing.s)
            .padding(.horizontal, SipSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                    .fill(SipColors.surfaceElevated)
            )
            .padding(SipSpacing.l)
        }
    }

    // MARK: - Text Entry Sheet

    private var textEntrySheet: some View {
        let searchState = textEntrySearchState
        let remoteSuggestions = visibleDiscoverySuggestions(excluding: searchState.suggestions)
        return NavigationStack {
            ScrollView {
                VStack(spacing: SipSpacing.xl) {
                    VStack(alignment: .leading, spacing: SipSpacing.s) {
                        Text("Enter beer name or description")
                            .font(SipTypography.subhead)
                            .foregroundColor(SipColors.textSecondary)
                        // Elevated input well (crit note 6) — the field sits one
                        // step above the sheet surface, never a system light border.
                        AutoFocusBeerTextField(text: $textEntryInput) {
                            submitTextEntry()
                        }
                        .accessibilityIdentifier("beerTextInput")
                    }
                    .padding(.horizontal)

                    // Exact input remains the immediate action. Local and
                    // connected matches are optional, brewery-qualified choices.
                    if !searchState.suggestions.isEmpty
                        || !remoteSuggestions.isEmpty
                        || searchState.customQuery != nil
                        || isDiscoveringBeers {
                        VStack(alignment: .leading, spacing: 0) {
                            if let customQuery = searchState.customQuery {
                                Button {
                                    submitCustomBeer(customQuery)
                                } label: {
                                    HStack(spacing: SipSpacing.m) {
                                        Image(systemName: "arrow.right.circle")
                                            .font(SipTypography.caption)
                                            .foregroundColor(SipColors.accent)
                                        Text("Check exactly \u{201c}\(customQuery)\u{201d}")
                                            .font(SipTypography.subhead)
                                            .foregroundColor(SipColors.textPrimary)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, SipSpacing.s)
                                    .padding(.horizontal, SipSpacing.m)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Check exact beer name \(customQuery)")
                                .accessibilityIdentifier("customBeerResult")

                                if !searchState.suggestions.isEmpty
                                    || !remoteSuggestions.isEmpty
                                    || isDiscoveringBeers {
                                    Divider()
                                        .background(SipColors.textSecondary.opacity(0.2))
                                        .padding(.leading, SipSpacing.m)
                                }
                            }

                            ForEach(Array(searchState.suggestions.enumerated()), id: \.offset) { index, suggestion in
                                Button {
                                    submitSuggestion(suggestion)
                                } label: {
                                    HStack(spacing: SipSpacing.m) {
                                        Image(systemName: "magnifyingglass")
                                            .font(SipTypography.caption)
                                            .foregroundColor(SipColors.textSecondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.name)
                                                .font(SipTypography.subhead)
                                                .foregroundColor(SipColors.textPrimary)
                                                .lineLimit(1)
                                            if let detail = suggestionDetail(suggestion) {
                                                Text(detail)
                                                    .font(SipTypography.caption)
                                                    .foregroundColor(SipColors.textSecondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, SipSpacing.s)
                                    .padding(.horizontal, SipSpacing.m)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("suggestionRow_\(index)")

                                if index < searchState.suggestions.count - 1
                                    || !remoteSuggestions.isEmpty
                                    || isDiscoveringBeers {
                                    Divider()
                                        .background(SipColors.textSecondary.opacity(0.2))
                                        .padding(.leading, SipSpacing.m)
                                }
                            }

                            if isDiscoveringBeers {
                                HStack(spacing: SipSpacing.m) {
                                    ProgressView()
                                        .tint(SipColors.accent)
                                    Text("Searching more beers\u{2026}")
                                        .font(SipTypography.caption)
                                        .foregroundColor(SipColors.textSecondary)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, SipSpacing.s)
                                .padding(.horizontal, SipSpacing.m)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("beerDiscoveryProgress")

                                if !remoteSuggestions.isEmpty {
                                    Divider()
                                        .background(SipColors.textSecondary.opacity(0.2))
                                        .padding(.leading, SipSpacing.m)
                                }
                            }

                            ForEach(Array(remoteSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                discoverySuggestionRow(suggestion, index: index)

                                if index < remoteSuggestions.count - 1 {
                                    Divider()
                                        .background(SipColors.textSecondary.opacity(0.2))
                                        .padding(.leading, SipSpacing.m)
                                }
                            }

                            if remoteSuggestions.contains(where: { $0.source == .catalogBeer }) {
                                Divider()
                                    .background(SipColors.textSecondary.opacity(0.2))
                                HStack(spacing: 4) {
                                    Text("Data:")
                                    Link("Catalog.beer", destination: URL(string: "https://catalog.beer")!)
                                    Text("\u{00B7}")
                                    Link(
                                        "CC BY 4.0",
                                        destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!
                                    )
                                    Spacer(minLength: 0)
                                }
                                .font(SipTypography.caption)
                                .foregroundColor(SipColors.textSecondary)
                                .padding(.vertical, SipSpacing.s)
                                .padding(.horizontal, SipSpacing.m)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                                .fill(SipColors.surfaceElevated)
                        )
                        .padding(.horizontal)
                        .animation(
                            .snappy(duration: 0.25),
                            value: searchState.suggestions.map(\.name) + remoteSuggestions.map(\.id)
                        )
                    }
                }
                .padding(.top, SipSpacing.xl)
                .padding(.bottom, SipSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // CTA rides just above the keyboard and stays reachable while
                // a long suggestion list scrolls independently.
                Button(action: {
                    submitTextEntry()
                }) {
                    Text("Check This Beer")
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .padding(.horizontal)
                .padding(.vertical, SipSpacing.s)
                .disabled(textEntryInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("checkBeerButton")
                .background(SipColors.surface)
            }
            // Sheets rest one step above the canvas: elevated surface token,
            // never raw #1A1A1E (round-2 crit #8) and never system/pure-#000.
            // The input well + suggestion card use surfaceElevated on top.
            .background(SipColors.surface.ignoresSafeArea())
            .onChange(of: textEntryInput) { _, newValue in
                scheduleBeerDiscovery(for: newValue)
            }
            .onDisappear {
                cancelBeerDiscovery()
                // A swipe-to-dismiss must not leave a stale query that cannot
                // trigger onChange when the sheet is opened again.
                textEntryInput = ""
            }
            .navigationTitle("Enter Beer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelBeerDiscovery()
                        textEntryInput = ""
                        showingTextEntry = false
                    }
                }
            }
        }
    }

    private func visibleDiscoverySuggestions(
        excluding localSuggestions: [ResolvedBeer]
    ) -> [BeerDiscoveryCandidate] {
        let localKeys = Set(localSuggestions.map {
            discoveryIdentityKey(name: $0.name, brewery: $0.brewery)
        })
        var seen = localKeys
        return discoverySuggestions.filter { candidate in
            seen.insert(discoveryIdentityKey(name: candidate.name, brewery: candidate.brewery)).inserted
        }
    }

    private func discoveryIdentityKey(name: String, brewery: String?) -> String {
        "\(BeerDiscoveryText.normalize(name))|\(BeerDiscoveryText.normalize(brewery ?? ""))"
    }

    private func discoverySuggestionRow(
        _ suggestion: BeerDiscoveryCandidate,
        index: Int
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                submitDiscoverySuggestion(suggestion)
            } label: {
                HStack(spacing: SipSpacing.m) {
                    Image(systemName: "globe.americas")
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.name)
                            .font(SipTypography.subhead)
                            .foregroundColor(SipColors.textPrimary)
                            .lineLimit(1)
                        if let detail = discoverySuggestionDetail(suggestion) {
                            Text(detail)
                                .font(SipTypography.caption)
                                .foregroundColor(SipColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, SipSpacing.s)
                .padding(.leading, SipSpacing.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Check \(suggestion.name) by \(suggestion.brewery ?? "unknown brewery")")
            .accessibilityValue("Source: \(suggestion.attributionLabel)")
            .accessibilityIdentifier("remoteSuggestionRow_\(index)")

            Link(destination: suggestion.sourceURL) {
                HStack(spacing: 3) {
                    Text(suggestion.attributionLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.right")
                }
                .font(SipTypography.caption)
                .foregroundColor(SipColors.accent)
                .frame(maxWidth: 108)
                .padding(.horizontal, SipSpacing.m)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Open source \(suggestion.attributionLabel)")
            .accessibilityIdentifier("remoteSuggestionSource_\(index)")
        }
    }

    private func discoverySuggestionDetail(_ beer: BeerDiscoveryCandidate) -> String? {
        var parts: [String] = []
        if let brewery = beer.brewery, !brewery.isEmpty { parts.append(brewery) }
        if let style = beer.styleName, !style.isEmpty {
            parts.append(style)
        } else if let style = beer.beerStyle {
            parts.append(style.rawValue)
        }
        if let abv = beer.abv {
            let format = abv.rounded() == abv ? "%.0f%% ABV" : "%.1f%% ABV"
            parts.append(String(format: format, abv))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func scheduleBeerDiscovery(for rawQuery: String) {
        beerDiscoveryGeneration += 1
        let generation = beerDiscoveryGeneration
        beerDiscoveryTask?.cancel()
        beerDiscoveryTask = nil
        discoverySuggestions = []
        isDiscoveringBeers = false

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = BeerDiscoveryText.normalize(query)
        guard normalized.count >= 3 else { return }

        beerDiscoveryTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled,
                      generation == beerDiscoveryGeneration,
                      showingTextEntry,
                      BeerDiscoveryText.normalize(textEntryInput) == normalized else { return }
                isDiscoveringBeers = true

                let results = try await BeerDiscoveryService.shared.search(
                    query: query,
                    limit: 6
                ) { catalogResults in
                    await MainActor.run {
                        guard !Task.isCancelled,
                              generation == beerDiscoveryGeneration,
                              showingTextEntry,
                              BeerDiscoveryText.normalize(textEntryInput) == normalized else { return }
                        discoverySuggestions = catalogResults
                    }
                }
                guard !Task.isCancelled,
                      generation == beerDiscoveryGeneration,
                      showingTextEntry,
                      BeerDiscoveryText.normalize(textEntryInput) == normalized else { return }
                discoverySuggestions = results
            } catch {
                // Exact input and local matches remain usable on every failure.
            }

            guard generation == beerDiscoveryGeneration else { return }
            isDiscoveringBeers = false
            beerDiscoveryTask = nil
        }
    }

    private func cancelBeerDiscovery() {
        beerDiscoveryGeneration += 1
        beerDiscoveryTask?.cancel()
        beerDiscoveryTask = nil
        discoverySuggestions = []
        isDiscoveringBeers = false
    }

    /// Compute discovery suggestions once per sheet render. The user's exact
    /// text is always a separate result because even an identically named
    /// catalog row can represent a different local beer.
    private var textEntrySearchState: TextEntrySearchState {
        let query = textEntryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return TextEntrySearchState(suggestions: [], customQuery: nil)
        }
        let suggestions = query.count >= 2
            ? BundledCatalog.shared.search(name: query, limit: 5)
            : []
        return TextEntrySearchState(
            suggestions: suggestions,
            customQuery: query
        )
    }

    /// "Sierra Nevada · Pale Ale" secondary line, nil when we know nothing.
    private func suggestionDetail(_ beer: ResolvedBeer) -> String? {
        var parts: [String] = []
        if let brewery = beer.brewery, !brewery.isEmpty { parts.append(brewery) }
        if let style = beer.style { parts.append(style.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// A suggestion is an explicit identity choice; its known facts enter the
    /// same local scorer as every other typed beer.
    private func submitSuggestion(_ suggestion: ResolvedBeer) {
        cancelBeerDiscovery()
        showingTextEntry = false
        textEntryInput = ""
        runScan(text: suggestion.name, selectedCatalogBeer: suggestion)
    }

    private func submitDiscoverySuggestion(_ suggestion: BeerDiscoveryCandidate) {
        cancelBeerDiscovery()
        showingTextEntry = false
        textEntryInput = ""
        runScan(text: suggestion.name, selectedCatalogBeer: suggestion.resolvedBeer)
    }

    private func submitCustomBeer(_ name: String) {
        cancelBeerDiscovery()
        showingTextEntry = false
        textEntryInput = ""
        runScan(text: name)
    }

    private func submitTextEntry() {
        let input = textEntryInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        cancelBeerDiscovery()
        showingTextEntry = false
        textEntryInput = ""
        runScan(text: input)
    }

    // MARK: - Actions

    private func requestCameraAndScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        presentScanner()
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

    private func presentScanner() {
        capturedImage = nil
        pendingLiveScanText = nil
        if LiveScannerView.isSupported && LiveScannerView.isAvailable {
            showingLiveScanner = true
        } else {
            showingCamera = true
        }
    }

    private func handleLiveCapture(_ capture: LiveScanCapture) {
        if let image = capture.image {
            pendingLiveScanText = capture.text
            capturedImage = image
        } else {
            runScan(recognizedText: capture.text, image: nil)
        }
    }

    // MARK: - Verdict-First Scan Flow (SPEED_PLAN §2)
    //
    // Stage 1 (on-device, typically a few seconds): OCR → menu detection → resolver (printed
    // style/ABV + bundled catalog) → TasteScorer → settled verdict on screen.
    // All pure compute (catalog decode, scoring) runs OFF the main actor.
    // Stage 2 (network, optional): one bounded enrichment call that may correct
    // metadata, never the visible recommendation or phase.

    private func runScan(image: UIImage) {
        guard startScan() else { return }
        let generation = scanGeneration
        let library = makeLibrarySnapshot()

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

            let outcome = await Task.detached(priority: .userInitiated) {
                Self.computeOutcome(fromText: text, path: "image", library: library)
            }.value
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

            await MainActor.run {
                guard generation == scanGeneration, case .recognizing = phase else { return }
                present(outcome, rawText: text, path: "image", latencyMs: latencyMs, image: image)
            }
        }
    }

    /// DataScanner has already recognized the frame continuously, so this path
    /// skips a second full-image OCR pass and reaches the same resolver directly.
    private func runScan(recognizedText: String, image: UIImage?) {
        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, startScan() else { return }
        let generation = scanGeneration
        let library = makeLibrarySnapshot()

        scanTask = Task(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.computeOutcome(fromText: text, path: "live", library: library)
            }.value
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

            await MainActor.run {
                guard generation == scanGeneration, case .recognizing = phase else { return }
                present(outcome, rawText: text, path: "live", latencyMs: latencyMs, image: image)
            }
        }
    }

    private func runScan(text: String, selectedCatalogBeer: ResolvedBeer? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard startScan() else { return }
        let generation = scanGeneration
        let library = makeLibrarySnapshot()

        scanTask = Task(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.computeOutcome(
                    fromText: trimmed,
                    path: "text",
                    library: library,
                    selectedCatalogBeer: selectedCatalogBeer
                )
            }.value
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
        menuRunnerUp = nil
        verdictHistorySnapshot = nil
        spinnerDegrees = 0
        scanningPhraseIndex = 0
        withAnimation { phase = .recognizing }
        return true
    }

    /// Snapshot all three stores on the main actor before scan work moves off
    /// thread. Journal sync records include tombstones, which are required to
    /// keep a deleted beer from reappearing through its legacy Drink mirror.
    private func makeLibrarySnapshot() -> BeerLibrarySnapshot {
        BeerLibrarySnapshot(
            journalRecords: journalStore.syncRecords,
            legacyDrinks: drinkStore.drinks,
            scans: scanStore.scans
        )
    }

    /// Stage 1 compute — pure and static so it can run off the main actor.
    nonisolated private static func computeOutcome(
        fromText text: String,
        path: String,
        library: BeerLibrarySnapshot,
        selectedCatalogBeer: ResolvedBeer? = nil
    ) -> ScanOutcome {
        let profile = TasteProfile.build(from: library.tasteRecords)
        let prefs = TastePreferences.current

        // Menu detection first (locked constraint: menu → ONE clear winner).
        // Two-plus parsed candidates means this is a list, not a label.
        let menuCandidates = MenuParser.parse(text)
        if menuCandidates.count >= 2 {
            let menuVerdict = MenuParser.evaluate(candidates: menuCandidates, profile: profile, preferences: prefs)
            guard let winner = menuVerdict.winner else {
                // A parsed candidate count of two always yields a ranked result;
                // retain the single-beer fallback if that invariant changes.
                return computeSingleBeerOutcome(
                    fromText: text,
                    path: path,
                    library: library,
                    profile: profile,
                    preferences: prefs,
                    selectedCatalogBeer: selectedCatalogBeer
                )
            }
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
                isMenu: true,
                menuRunnerUp: menuVerdict.ranked.dropFirst().first.map {
                    Scan(
                        beerName: $0.name,
                        style: $0.style?.rawValue,
                        abv: $0.abv,
                        verdict: $0.assessment.verdict,
                        explanation: "Runner-up from this menu. \(sentenceCase($0.assessment.shortReason))"
                    )
                }
            )
        }

        return computeSingleBeerOutcome(
            fromText: text,
            path: path,
            library: library,
            profile: profile,
            preferences: prefs,
            selectedCatalogBeer: selectedCatalogBeer
        )
    }

    /// Single-beer path: fuse printed style/ABV with a bundled-catalog match.
    nonisolated private static func computeSingleBeerOutcome(
        fromText text: String,
        path: String,
        library: BeerLibrarySnapshot,
        profile: TasteProfile,
        preferences prefs: TastePreferences,
        selectedCatalogBeer: ResolvedBeer?
    ) -> ScanOutcome {
        let resolved = path == "text"
            ? BeerResolver.resolveTyped(
                recognizedText: text,
                selectedCatalogBeer: selectedCatalogBeer
            )
            : BeerResolver.resolve(recognizedText: text, using: BundledCatalog.shared)
        let (name, nameIsGuess) = displayName(fromText: text, resolved: resolved, path: path)
        let trustedFacts = ScanRecommendationSettlementPolicy.trustedFacts(
            from: resolved,
            recognizedText: text,
            nameIsGuess: nameIsGuess,
            isTypedInput: path == "text"
        )
        let assessment = TasteScorer.assessWithExactHistory(
            name: name,
            brewery: trustedFacts.brewery,
            style: trustedFacts.style,
            abv: trustedFacts.abv,
            library: library,
            profile: profile,
            preferences: prefs,
            allowExactMatch: path == "text" || !nameIsGuess
        )
        let settled = ScanRecommendationSettlementPolicy.settleInitial(
            proposedVerdict: assessment.verdict,
            proposedExplanation: sentenceCase(assessment.shortReason),
            proposedScore: assessment.score,
            nameIsGuess: nameIsGuess,
            resolvedStyle: trustedFacts.style,
            source: resolved.source,
            isTypedInput: path == "text",
            isMenu: false
        )

        let scan = Scan(
            beerName: name,
            brand: settled.keepResolvedFacts ? trustedFacts.brewery : nil,
            style: settled.keepResolvedFacts ? trustedFacts.style?.rawValue : nil,
            abv: settled.keepResolvedFacts ? trustedFacts.abv : nil,
            verdict: settled.verdict,
            explanation: settled.explanation,
            wantToTry: false,
            origin: nil,
            factSource: resolved.factSource
        )
        return ScanOutcome(
            scan: scan,
            source: resolved.source.rawValue,
            score: settled.score,
            nameIsGuess: nameIsGuess,
            startedStyleless: scan.style == nil,
            isMenu: false,
            menuRunnerUp: nil
        )
    }

    nonisolated private static func menuExplanation(winner: TasteScorer.AssessedCandidate, totalCandidates: Int) -> String {
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
        menuRunnerUp = outcome.menuRunnerUp
        verdictHistorySnapshot = outcome.nameIsGuess
            ? nil
            : makeLibrarySnapshot()
                .exactItem(name: outcome.scan.beerName, brewery: outcome.scan.brand)?
                .latestEncounter
        let willRefine = EnrichmentPolicy.shouldStart(
            nameIsGuess: outcome.nameIsGuess,
            startedStyleless: outcome.startedStyleless,
            isMenu: outcome.isMenu,
            onDeviceAvailable: OnDeviceBeerKnowledge.isAvailable,
            onlineAvailable: outcome.nameIsGuess
                ? ScanningPipeline.shared.canEnrichVision
                : ScanningPipeline.shared.canEnrichOnline
        )
        withAnimation { phase = .verdict(outcome.scan, refining: willRefine) }
        if willRefine {
            startRefinement(for: outcome.scan, text: rawText, outcome: outcome, image: image)
        }

        if let image {
            persistScanPhoto(image, for: outcome.scan.id)
        }
    }

    /// Persist the captured frame without delaying the verdict. The same local
    /// file is available when the user returns through Want to Try or a reminder.
    private func persistScanPhoto(_ image: UIImage, for scanID: UUID) {
        Task {
            guard let fileName = await drinkStore.savePhoto(image, for: scanID) else { return }
            await MainActor.run {
                guard var stored = scanStore.scans.first(where: { $0.id == scanID }) else { return }
                stored.photoFileName = fileName
                scanStore.updateScan(stored)
                if case .verdict(let visible, let refining) = phase, visible.id == scanID {
                    phase = .verdict(stored, refining: refining)
                }
            }
        }
    }

    /// Stage 2: bounded background enrichment. The provider supplies facts only;
    /// corrected metadata may update in place, but the visible recommendation
    /// is an immutable snapshot of the settled local answer.
    private func startRefinement(for scan: Scan, text: String, outcome: ScanOutcome, image: UIImage?) {
        let nameIsGuess = outcome.nameIsGuess
        let startedStyleless = outcome.startedStyleless

        refineTask = Task(priority: .utility) {
            // Weak or guessed reads get the frame too, so a graphic label with
            // garbage OCR can still be identified by the vision fallback.
            let sendImage = (nameIsGuess || text.count < 15) ? image : nil
            let enrichment = await ScanningPipeline.shared.enrich(
                text: text,
                candidateName: scan.beerName,
                image: sendImage,
                nameIsGuess: nameIsGuess,
                startedStyleless: startedStyleless,
                deviceVerdict: scan.verdict
            )
            if Task.isCancelled { return }

            await MainActor.run {
                // Only patch the scan that's still on screen.
                guard case .verdict(var current, _) = phase, current.id == scan.id else { return }
                if let e = enrichment {
                    let correctedName = nameIsGuess ? e.name : nil
                    let nameChanged = correctedName != nil && correctedName != current.beerName
                    if let correctedName {
                        // Replace the guessed identity as one unit. Keeping a
                        // stale catalog style/ABV beside a corrected name can
                        // produce a confidently wrong recommendation.
                        current.beerName = correctedName
                        current.brand = e.brand
                        current.style = e.style?.rawValue
                        current.abv = e.abv
                        current.origin = e.origin
                    } else {
                        if current.brand == nil, let brand = e.brand { current.brand = brand }
                        if current.style == nil, let style = e.style { current.style = style.rawValue }
                        if current.abv == nil, let abv = e.abv { current.abv = abv }
                        if current.origin == nil, let origin = e.origin { current.origin = origin }
                    }

                    let resolvedStyle = current.style.flatMap { rawValue in
                        BeerStyle.allCases.first {
                            $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame
                        }
                    }
                    let library = makeLibrarySnapshot()
                    let assessment = TasteScorer.assessWithExactHistory(
                        name: current.beerName,
                        brewery: current.brand,
                        style: resolvedStyle,
                        abv: current.abv,
                        library: library,
                        profile: TasteProfile.build(from: library.tasteRecords),
                        preferences: TastePreferences.current
                    )
                    let stableRecommendation = ScanRecommendationSettlementPolicy.settleRefinement(
                        visibleVerdict: current.verdict,
                        visibleExplanation: current.explanation,
                        proposedVerdict: assessment.verdict,
                        proposedExplanation: Self.sentenceCase(assessment.shortReason),
                        proposedScore: assessment.score,
                        freezeVisibleRecommendation: outcome.nameIsGuess
                    )
                    current.verdict = stableRecommendation.verdict
                    current.explanation = stableRecommendation.explanation
                    // A guessed identity keeps the already-shown recommendation
                    // frozen by policy. Do not attach newly discovered personal
                    // history to that old explanation; the next explicit check
                    // will use the corrected identity end-to-end.
                    verdictHistorySnapshot = outcome.nameIsGuess
                        ? nil
                        : library
                            .exactItem(name: current.beerName, brewery: current.brand)?
                            .latestEncounter
                    scanStore.updateScan(current)
                    if nameChanged, current.wantToTry {
                        // Same identifier → replaces the pending follow-up, so the
                        // notification names the corrected beer. Only saved beers
                        // have a follow-up pending to correct.
                        NotificationService.shared.scheduleFollowUpIfAuthorized(for: current)
                    }
                }
                withAnimation(.smooth(duration: 0.35)) {
                    phase = .verdict(current, refining: false)
                }
            }
        }
    }

    /// Choose what to show as the beer's name, and whether it's a guess that
    /// network refinement is allowed to replace. Trust is graded by catalog
    /// confidence — a 0.6 fuzzy hit must not permanently rename the scan.
    /// Trailing list punctuation on a derived name ("HAZY IPA,") reads as a
    /// bug everywhere the name renders — shed it from every non-catalog name.
    nonisolated private static let nameEdgeNoise = CharacterSet(charactersIn: " \t.,;:-—|•·")

    nonisolated private static func displayName(fromText text: String, resolved: ResolvedBeer, path: String) -> (name: String, isGuess: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let confidence = resolved.confidence {
            // High-confidence catalog hit: canonical name is authoritative.
            if confidence >= 0.9 { return (resolved.name, false) }
            // Moderate hit: show the canonical name, but refinement may correct it.
            return (resolved.name, true)
        }

        // The resolver filters bottle-neck dates and legal copy from
        // multi-line OCR. Its candidate is more useful than the page's first
        // line when no catalog entry matched.
        if path != "text", trimmed.contains("\n"), resolved.name != trimmed {
            return (resolved.name, true)
        }

        // No catalog hit. Typed input is the user's own words — trust it.
        // A single-line OCR read is still machine output, so it stays replaceable.
        if !trimmed.contains("\n") {
            let cleaned = String(trimmed.prefix(60)).trimmingCharacters(in: nameEdgeNoise)
            return (cleaned.isEmpty ? String(trimmed.prefix(60)) : cleaned, path != "text")
        }

        // Multi-line OCR blob (that didn't parse as a menu): best-guess the
        // first non-empty line and let refinement supply the real name.
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? trimmed
        let cleaned = String(firstLine.prefix(60)).trimmingCharacters(in: nameEdgeNoise)
        return (cleaned.isEmpty ? String(firstLine.prefix(60)) : cleaned, true)
    }

    /// "matches your love of IPA" → "Matches your love of IPA."
    nonisolated private static func sentenceCase(_ fragment: String) -> String {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        let capitalized = first.uppercased() + trimmed.dropFirst()
        return capitalized.hasSuffix(".") || capitalized.hasSuffix("!") ? capitalized : capitalized + "."
    }

    private func saveForLater(_ scan: Scan) {
        guard !savedForLater else { return }
        // Photo persistence is intentionally asynchronous so it cannot delay
        // the verdict. Merge from the store before toggling this flag so a tap
        // landing at the same moment cannot overwrite the new filename.
        var updated = scanStore.scans.first(where: { $0.id == scan.id }) ?? scan
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
        menuRunnerUp = nil
        verdictHistorySnapshot = nil
        pendingLiveScanText = nil
        capturedImage = nil
        spinnerDegrees = 0
        scanningPhraseIndex = 0
        withAnimation { phase = .idle }
    }
}

/// Keeps focus state inside the presented sheet's focus scope. A FocusState
/// owned by CheckTabView can be set before the sheet's text field is mounted,
/// which leaves the rescue path requiring an extra tap.
private struct AutoFocusBeerTextField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("e.g. Lagunitas IPA, hoppy pale ale...", text: $text)
            .textFieldStyle(.plain)
            .font(SipTypography.body)
            .foregroundColor(SipColors.textPrimary)
            .tint(SipColors.accent)
            .focused($isFocused)
            .submitLabel(.search)
            .onSubmit(onSubmit)
            .padding(SipSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                    .fill(SipColors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                    .strokeBorder(isFocused ? SipColors.accent : SipColors.textSecondary.opacity(0.25), lineWidth: 1)
            )
            .animation(.snappy(duration: 0.25), value: isFocused)
            .task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                isFocused = true
            }
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
                .environmentObject(JournalStore())
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
                .environmentObject(JournalStore())
                .previewDisplayName("Empty State")
        }
    }
}
