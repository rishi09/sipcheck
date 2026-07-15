import SwiftUI

// MARK: - Flow Variants (Onboarding Lab)

/// The onboarding flow shapes the Lab can switch between. Raw values are the
/// exact strings the Settings "Onboarding Lab" section writes to the
/// `onboardingFlowVariant` UserDefaults key — both sides hardcode them.
enum OnboardingVariant: String, CaseIterable, Identifiable {
    /// Classic flow: had-before picker + full taste quiz.
    case control
    /// Default: go-to picker + stay-away picker; stay-away completes.
    case goToStayAway
    /// Same as the default plus a vibe-only quiz at the end.
    case goToStayAwayPlusVibe

    var id: String { rawValue }

    var pages: [OnboardingPage] {
        switch self {
        case .control:
            return [.story(index: 0), .story(index: 1), .story(index: 2),
                    .legacyBeerPicker,
                    .quiz(includeAdventure: true, includeDislikes: true)]
        case .goToStayAway:
            return [.story(index: 0), .story(index: 1), .story(index: 2),
                    .goToPicker,
                    .stayAwayPicker]
        case .goToStayAwayPlusVibe:
            return [.story(index: 0), .story(index: 1), .story(index: 2),
                    .goToPicker,
                    .stayAwayPicker,
                    .quiz(includeAdventure: false, includeDislikes: false)]
        }
    }
}

enum OnboardingPage {
    case story(index: Int)           // 0, 1, 2
    case legacyBeerPicker
    case goToPicker
    case stayAwayPicker
    case quiz(includeAdventure: Bool, includeDislikes: Bool)

    /// Pages with their own CTA blocks hide the system page dots so buttons
    /// never fight the page indicator for the same bottom band.
    var hasOwnCTABlock: Bool {
        if case .story = self { return false }
        return true
    }
}

// MARK: - Shared option pools

/// The 16 recognizable picker beers — shared by the legacy, go-to, and
/// stay-away pickers so saved picks restore identically on every page.
/// Internal (not file-private): Settings' TastePreferencesEditorView renders
/// the same pool so edited picks stay restorable here.
let onboardingBeerOptions = [
    "Modelo", "Corona", "Heineken", "Blue Moon",
    "Sam Adams", "Guinness", "Sierra Nevada", "Lagunitas",
    "Hazy Little Thing", "Coors Light", "Bud Light", "Stella Artois",
    "Allagash White", "Dogfish Head", "Stone IPA", "Goose Island"
]

/// Style chips offered on the go-to and stay-away pickers (and Settings'
/// taste editor — internal so both surfaces stay in lockstep).
let onboardingStyleChips: [BeerStyle] = BeerStyle.allCases.filter { $0 != .other }

/// Pluralized DISPLAY labels for the style chips. Display only — persisted
/// values are always `BeerStyle.rawValue`, never these. Internal: Settings'
/// taste editor shows the same labels.
func styleChipLabel(_ style: BeerStyle) -> String {
    switch style {
    case .ipa: return "IPAs"
    case .paleAle: return "Pale ales"
    case .lager: return "Lagers"
    case .pilsner: return "Pilsners"
    case .stout: return "Stouts"
    case .porter: return "Porters"
    case .wheat: return "Wheat beers"
    case .sour: return "Sours"
    case .amber: return "Ambers"
    case .brownAle: return "Brown ales"
    case .belgian: return "Belgians"
    case .other: return style.rawValue
    }
}

/// Exemplar brand anchors for the style chips — one widely recognizable beer
/// (or style descriptor) per style, so answering never requires beer
/// vocabulary: "Stouts — like Guinness". The brand name is the input
/// language; the style is only the stored output. Display only, never
/// persisted. Internal: Settings' taste editor shows the same anchors.
func styleChipAnchor(_ style: BeerStyle) -> String? {
    switch style {
    case .ipa: return "like Lagunitas"
    case .paleAle: return "like Sierra Nevada"
    case .lager: return "like Modelo"
    case .pilsner: return "like Stella"
    case .stout: return "like Guinness"
    case .porter: return "like Founders Porter"
    case .wheat: return "like Blue Moon"
    case .sour: return "like a gose"
    case .amber: return "like Fat Tire"
    case .brownAle: return "like Newcastle"
    case .belgian: return "like Chimay"
    case .other: return nil
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Onboarding Lab variant switches — written by Settings' Onboarding Lab,
    // read live here so the next preview picks up changes with zero plumbing.
    @AppStorage("onboardingFlowVariant") private var flowVariantRaw = OnboardingVariant.goToStayAway.rawValue
    @AppStorage("onboardingCopyVariantPage1") private var copyVariantPage1 = "A"
    @AppStorage("onboardingScanVignette") private var scanVignetteRaw = "full"
    @AppStorage("onboardingPickerCopyVariant") private var pickerCopyVariant = "primary"

    /// Lab-preview hook: when set, finishing (or the close button) calls this
    /// instead of flipping `hasCompletedOnboarding` — a preview must never
    /// touch real completion state.
    var onFinish: (() -> Void)? = nil

    @State private var currentPage = 0

    private var variant: OnboardingVariant {
        OnboardingVariant(rawValue: flowVariantRaw) ?? .goToStayAway
    }

    /// Lab previews (`onFinish != nil`) must be non-destructive: every page
    /// stays fully interactive in memory, but ALL persistence is suppressed —
    /// Settings' footer promises "Preview never touches your taste data."
    private var isPreview: Bool { onFinish != nil }

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(0..<variant.pages.count, id: \.self) { idx in
                pageView(
                    for: variant.pages[idx],
                    tag: idx,
                    isLast: idx == variant.pages.count - 1
                )
                .tag(idx)
            }
        }
        // min() guards a live flow-variant switch shrinking the page count
        // while a later page is selected.
        .tabViewStyle(.page(indexDisplayMode: variant.pages[min(currentPage, variant.pages.count - 1)].hasOwnCTABlock ? .never : .always))
        // A live flow-variant switch can shrink the page count, leaving the
        // selection pointing at a removed tag (blank TabView). Restart the
        // new flow from its first page.
        .onChange(of: flowVariantRaw) { _, _ in
            currentPage = 0
        }
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(SipColors.background.ignoresSafeArea())
        .accessibilityIdentifier("onboardingPreviewRoot")
        .overlay(alignment: .topTrailing) {
            if onFinish != nil {
                Button(action: finish) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("onboardingPreviewCloseButton")
                .padding(SipSpacing.l)
            }
        }
    }

    /// The ONLY completion point: Lab previews dismiss via `onFinish`; the
    /// real first run flips `hasCompletedOnboarding`.
    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            hasCompletedOnboarding = true
        }
    }

    private func advanceAction(from tag: Int, isLast: Bool) -> () -> Void {
        if isLast { return finish }
        return {
            withAnimation(.smooth) {
                currentPage = tag + 1
            }
        }
    }

    @ViewBuilder
    private func pageView(for page: OnboardingPage, tag: Int, isLast: Bool) -> some View {
        switch page {
        case .story(let index):
            storyPage(index: index, tag: tag, isLast: isLast)
        case .legacyBeerPicker:
            BeerPickerPage(
                isPreview: isPreview,
                onAdvance: advanceAction(from: tag, isLast: isLast)
            )
        case .goToPicker:
            GoToPickerPage(
                copyVariant: pickerCopyVariant,
                isPreview: isPreview,
                onAdvance: advanceAction(from: tag, isLast: isLast)
            )
        case .stayAwayPicker:
            StayAwayPickerPage(
                copyVariant: pickerCopyVariant,
                isLast: isLast,
                isPreview: isPreview,
                onAdvance: advanceAction(from: tag, isLast: isLast)
            )
        case .quiz(let includeAdventure, let includeDislikes):
            TasteQuizPage(
                includeAdventure: includeAdventure,
                includeDislikes: includeDislikes,
                isPreview: isPreview,
                onFinish: finish
            )
        }
    }

    private var pageOneCopy: (title: String, description: String) {
        switch copyVariantPage1 {
        case "B": return ("Stop guessing. Buy better beer.", "SipCheck learns what you actually like.")
        case "C": return ("Never waste a sip again", "Buy better beer, every single time.")
        // D = A's punchline warranted by the palate-vs-crowd contrast — the
        // body line is the differentiator, not a mechanism clause.
        case "D": return ("Buy better beer.", "Picked for your taste, not the crowd's.")
        default:  return ("Buy better beer.", "Know what you'll like before you buy.")
        }
    }

    private func storyPage(index: Int, tag: Int, isLast: Bool) -> StoryPage {
        let onAdvance = advanceAction(from: tag, isLast: isLast)
        let ctaID = "onboardingContinuePage\(index)"
        switch index {
        case 0:
            let copy = pageOneCopy
            return StoryPage(
                icon: "mug.fill",
                title: copy.title,
                description: copy.description,
                // Beer-native amber hero (matches the Check idle motif) — the
                // age gate already owns the teal mug; don't repeat it here.
                iconStyle: AnyShapeStyle(StyleGradient.gradient(for: "IPA")),
                continueAccessibilityID: ctaID,
                onAdvance: onAdvance
            )
        case 1:
            if scanVignetteRaw == "icon" {
                // No animation to carry "scan a label", so the words do it.
                return StoryPage(
                    icon: "camera.fill",
                    title: "Scan a label, get a verdict",
                    description: "Based on your taste, not the hype.",
                    continueAccessibilityID: ctaID,
                    onAdvance: onAdvance
                )
            }
            return StoryPage(
                icon: "camera.fill",
                title: "Try it. Skip it. Your call.",
                description: "Point your camera. Get your verdict.",
                hero: AnyView(ScanVignetteView(variant: ScanVignetteVariant(rawValue: scanVignetteRaw) ?? .full)),
                continueAccessibilityID: ctaID,
                onAdvance: onAdvance
            )
        default:
            return StoryPage(
                icon: "sparkles",
                title: "The more you log, the better it gets",
                description: "Every beer you rate teaches SipCheck your taste. Your picks get sharper every week.",
                continueAccessibilityID: ctaID,
                onAdvance: onAdvance
            )
        }
    }
}

// MARK: - Story Page

private struct StoryPage: View {
    let icon: String
    let title: String
    let description: String
    /// Optional custom hero (e.g. the scan vignette). When nil, the SF Symbol
    /// `icon` renders in its place.
    var hero: AnyView? = nil
    var iconStyle: AnyShapeStyle = AnyShapeStyle(SipColors.accent)
    let continueAccessibilityID: String
    let onAdvance: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 80

    var body: some View {
        VStack(spacing: SipSpacing.xl) {
            Spacer()
            if let hero {
                hero
            } else {
                Image(systemName: icon)
                    .font(.system(size: heroIconSize))
                    .foregroundStyle(iconStyle)
            }
            Text(title)
                .font(SipTypography.title)
                .foregroundColor(SipColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(description)
                .font(SipTypography.body)
                .foregroundColor(SipColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()

            // Swipe-only advance is undiscoverable — every story page gets an
            // explicit primary Continue.
            Button(action: onAdvance) {
                Text("Continue")
            }
            .buttonStyle(SipPrimaryButtonStyle())
            .accessibilityIdentifier(continueAccessibilityID)
            .padding(.horizontal, SipSpacing.xl)
            // Clear the system page dots below the CTA.
            .padding(.bottom, 56)
        }
    }
}

// MARK: - Picker Page Scaffold

/// Shared chrome for every CTA-block page: scrolling header + content above a
/// reserved bottom band (one primary CTA and one quiet skip). Used by the
/// legacy picker, both new pickers, and the
/// taste quiz.
private struct PickerPageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let primaryTitle: String
    let primaryAccessibilityID: String
    var primaryDisabled: Bool = false
    let primaryAction: () -> Void
    let quietTitle: String
    let quietAccessibilityID: String
    let quietAction: () -> Void
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        primaryTitle: String,
        primaryAccessibilityID: String,
        primaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void,
        quietTitle: String,
        quietAccessibilityID: String,
        quietAction: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.primaryAccessibilityID = primaryAccessibilityID
        self.primaryDisabled = primaryDisabled
        self.primaryAction = primaryAction
        self.quietTitle = quietTitle
        self.quietAccessibilityID = quietAccessibilityID
        self.quietAction = quietAction
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SipSpacing.xl) {
                VStack(alignment: .leading, spacing: SipSpacing.s) {
                    Text(title)
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                    Text(subtitle)
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
                .padding(.top, SipSpacing.xl)

                content()
            }
            .padding(.horizontal, SipSpacing.xl)
            .padding(.bottom, SipSpacing.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: SipSpacing.m) {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .disabled(primaryDisabled)
                .accessibilityIdentifier(primaryAccessibilityID)

                Button(action: quietAction) {
                    Text(quietTitle)
                }
                .buttonStyle(SipQuietButtonStyle())
                .accessibilityIdentifier(quietAccessibilityID)
            }
            .padding(.horizontal, SipSpacing.xl)
            .padding(.top, SipSpacing.m)
            .padding(.bottom, SipSpacing.s)
            .background(SipColors.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(SipColors.textSecondary.opacity(0.16))
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Legacy Beer Picker Page (control variant — strings unchanged)

private struct BeerPickerPage: View {
    /// Lab preview: chips stay interactive but nothing persists.
    let isPreview: Bool
    let onAdvance: () -> Void

    @State private var selectedBeers: Set<String> = []
    /// Monotonic guard: only the newest persistSelections snapshot may write.
    @State private var persistGeneration = 0

    var body: some View {
        PickerPageScaffold(
            title: "Beers you've had before?",
            subtitle: "Tap any you've tried. We'll use it to calibrate your taste.",
            primaryTitle: "Next →",
            primaryAccessibilityID: "onboardingPickerNext",
            primaryAction: advance,
            quietTitle: "Skip",
            quietAccessibilityID: "onboardingPickerSkip",
            // Skip must NOT persist — write-through on every tap already
            // stored real picks; a skip only moves on.
            quietAction: onAdvance
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: SipSpacing.s)],
                alignment: .leading,
                spacing: SipSpacing.s
            ) {
                ForEach(onboardingBeerOptions, id: \.self) { beer in
                    ChipButton(
                        label: beer,
                        isSelected: selectedBeers.contains(beer)
                    ) {
                        toggleBeer(beer)
                    }
                }
            }
        }
        .onAppear {
            // Replay/reinstall: restore prior picks so the first new tap's
            // write-through doesn't overwrite a multi-beer selection (and its
            // synced seed styles) with a single beer.
            if selectedBeers.isEmpty {
                selectedBeers = Set(TastePreferences.savedKnownBeers).intersection(Set(onboardingBeerOptions))
            }
        }
    }

    private func toggleBeer(_ beer: String) {
        if selectedBeers.contains(beer) {
            selectedBeers.remove(beer)
        } else {
            selectedBeers.insert(beer)
        }
        // Write-through on every tap: swiping to the next page (instead of
        // tapping Next) used to silently discard all picks.
        persistSelections()
    }

    /// Persist the picks AND the styles they resolve to — the seed the verdict
    /// engine actually consumes. Resolution runs off-main (catalog decode);
    /// the generation guard makes the LATEST tap's snapshot win — unordered
    /// task completion must not let a stale subset be the last write.
    private func persistSelections() {
        guard !isPreview else { return } // Lab preview never touches taste data
        persistGeneration += 1
        let generation = persistGeneration
        let beers = Array(selectedBeers)

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                // Same catalog+inference fusion the scan path uses, so the
                // seed style for a beer matches what scanning it would resolve.
                Array(Set(beers.compactMap {
                    (TastePreferences.styleForOnboardingBeer($0)
                        ?? BeerResolver.resolve(recognizedText: $0, using: BundledCatalog.shared).style)?.rawValue
                })).sorted()
            }.value
            guard generation == persistGeneration else { return } // stale snapshot
            TastePreferences.saveKnownBeers(beers, seedStyles: styles)
        }
    }

    private func advance() {
        persistSelections()
        onAdvance()
    }
}

// MARK: - Go-To Picker Page

/// "What's your go-to?" — positive cold-start seed: style chips, the beer
/// grid, and an optional adventure row. Chips the stay-away page already
/// claimed render locked (dimmed, no-op) rather than hidden.
private struct GoToPickerPage: View {
    /// "primary" | "alt" — the Lab's `onboardingPickerCopyVariant` value.
    let copyVariant: String
    /// Lab preview: chips stay interactive but nothing persists.
    let isPreview: Bool
    let onAdvance: () -> Void

    @State private var selectedBeers: Set<String> = []
    @State private var selectedGoToStyles: Set<BeerStyle> = []
    @State private var selectedAdventure: String? = nil
    /// Monotonic guard: only the newest persistSelections snapshot may write.
    @State private var persistGeneration = 0

    // Cross-exclusion: anything already claimed by the stay-away page is
    // locked here (visible but inert) — never hidden. Computed at render
    // time, NOT captured in onAppear: a paged TabView pre-builds neighbor
    // pages and fires their appearance early, so a stored snapshot would
    // freeze pre-answer state and the locks would never track real picks.
    private var lockedBeers: Set<String> {
        Set(TastePreferences.savedAvoidBeers).intersection(Set(onboardingBeerOptions))
    }
    /// Explicit stay-away style CHIPS only (the style rawValues inside the
    /// mixed picks list) — beer-derived style collisions ("avoid Guinness" →
    /// Stout) stay at the scorer level; the UI never locks a chip the user
    /// didn't explicitly claim. Mirrors the stay-away page's lock source.
    private var lockedStyles: Set<BeerStyle> {
        Set(TastePreferences.savedAvoidBeers.compactMap { BeerStyle(rawValue: $0) })
    }

    private var title: String {
        copyVariant == "alt" ? "What's in your fridge right now?" : "What's your go-to?"
    }

    // Present/past indicative only — recall of purchases that already happen,
    // never a conditional "what would you enjoy?".
    private var subtitle: String {
        copyVariant == "alt"
            ? "Tap what's actually in there."
            : "Tap the beers you buy without thinking."
    }

    var body: some View {
        PickerPageScaffold(
            title: title,
            subtitle: subtitle,
            primaryTitle: "Next →",
            primaryAccessibilityID: "onboardingPickerNext",
            primaryAction: advance,
            quietTitle: "Skip",
            quietAccessibilityID: "onboardingPickerSkip",
            // Skip never writes — real picks were already written through.
            quietAction: onAdvance
        ) {
            // Styles first: on a label the style is the signal, and one style
            // chip seeds more than any single beer.
            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Styles")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                // Wider cells than the beer grid: the exemplar anchor line
                // ("like Sierra Nevada") must fit on one line.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: SipSpacing.s)],
                    alignment: .leading,
                    spacing: SipSpacing.s
                ) {
                    ForEach(onboardingStyleChips, id: \.self) { style in
                        ChipButton(
                            label: styleChipLabel(style),
                            isSelected: selectedGoToStyles.contains(style),
                            lockedCaption: lockedStyles.contains(style) ? "stay-away" : nil,
                            anchorCaption: styleChipAnchor(style)
                        ) {
                            toggleStyle(style)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Beers")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: SipSpacing.s)],
                    alignment: .leading,
                    spacing: SipSpacing.s
                ) {
                    ForEach(onboardingBeerOptions, id: \.self) { beer in
                        ChipButton(
                            label: beer,
                            isSelected: selectedBeers.contains(beer),
                            lockedCaption: lockedBeers.contains(beer) ? "stay-away" : nil
                        ) {
                            toggleBeer(beer)
                        }
                    }
                }
            }

            // Optional — answering never gates Next; persisted via the
            // targeted saveAdventure so it can't blank a real vibe.
            QuizQuestion(
                question: "How adventurous?",
                options: TastePreferences.adventureOptions,
                multiSelect: false,
                selectedSingle: $selectedAdventure,
                selectedMulti: .constant([])
            )
        }
        .onAppear {
            restoreSavedSelections()
        }
        .onChange(of: selectedAdventure) { _, newValue in
            // Write-through on every tap. Targeted writer: the 3-key quiz
            // save() would blank a real vibe saved elsewhere.
            // Preview-suppressed like every other persistence path.
            if let newValue, !isPreview {
                TastePreferences.saveAdventure(newValue)
            }
        }
    }

    /// Replay/reinstall: restore prior picks (guard-if-empty per field) so the
    /// first new tap's write-through doesn't overwrite a fuller saved set.
    private func restoreSavedSelections() {
        let current = TastePreferences.current
        if selectedBeers.isEmpty {
            selectedBeers = Set(TastePreferences.savedKnownBeers).intersection(Set(onboardingBeerOptions))
        }
        if selectedGoToStyles.isEmpty {
            selectedGoToStyles = Set(current.goToStyles.compactMap { BeerStyle(rawValue: $0) })
        }
        if selectedAdventure == nil, !current.adventure.isEmpty {
            selectedAdventure = current.adventure
        }
    }

    private func toggleStyle(_ style: BeerStyle) {
        if selectedGoToStyles.contains(style) {
            selectedGoToStyles.remove(style)
        } else {
            selectedGoToStyles.insert(style)
        }
        // Write-through on every tap.
        persistSelections()
    }

    private func toggleBeer(_ beer: String) {
        if selectedBeers.contains(beer) {
            selectedBeers.remove(beer)
        } else {
            selectedBeers.insert(beer)
        }
        // Write-through on every tap: swiping to the next page (instead of
        // tapping Next) must not silently discard picks.
        persistSelections()
    }

    /// Persist the picks, the explicit style chips, AND the styles the beer
    /// picks resolve to — the seed the verdict engine actually consumes.
    /// Resolution runs off-main (catalog decode); the generation guard makes
    /// the LATEST tap's snapshot win — unordered task completion must not let
    /// a stale subset be the last write.
    private func persistSelections() {
        guard !isPreview else { return } // Lab preview never touches taste data
        persistGeneration += 1
        let generation = persistGeneration
        let beers = Array(selectedBeers)
        // Snapshot the chips BEFORE the async hop — the save writes all three
        // keys, so a stale chip set must never ride along with a fresh
        // beer resolution.
        let styleChips = selectedGoToStyles.map(\.rawValue).sorted()

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                // Same catalog+inference fusion the scan path uses, so the
                // seed style for a beer matches what scanning it would resolve.
                Array(Set(beers.compactMap {
                    (TastePreferences.styleForOnboardingBeer($0)
                        ?? BeerResolver.resolve(recognizedText: $0, using: BundledCatalog.shared).style)?.rawValue
                })).sorted()
            }.value
            guard generation == persistGeneration else { return } // stale snapshot
            TastePreferences.saveGoTo(beers: beers, styleChips: styleChips, seedStyles: styles)
        }
    }

    private func advance() {
        persistSelections()
        onAdvance()
    }
}

// MARK: - Stay-Away Picker Page

/// "What do you always walk past?" — the negative seed (founder point 4).
/// Persists the raw picks (beer names + style rawValues) plus the styles they
/// resolve to; the scorer's avoid set is checked before liked weights.
private struct StayAwayPickerPage: View {
    /// "primary" | "alt" — the Lab's `onboardingPickerCopyVariant` value.
    let copyVariant: String
    /// When this is the flow's last page its CTA completes onboarding.
    let isLast: Bool
    /// Lab preview: chips stay interactive but nothing persists.
    let isPreview: Bool
    let onAdvance: () -> Void

    @State private var selectedAvoidBeers: Set<String> = []
    @State private var selectedAvoidStyles: Set<BeerStyle> = []
    /// Styles the current picks resolve to — the inline echo's source.
    /// Display-only mirror of what persistAvoidSelections saves, so it also
    /// updates in Lab previews (resolution is read-only; persistence isn't).
    @State private var echoedAvoidStyles: [String] = []
    /// Monotonic guard (own counter, parallel to the go-to page's): only the
    /// newest persistAvoidSelections snapshot may write.
    @State private var avoidGeneration = 0

    // Cross-exclusion: anything already claimed by the go-to page is locked
    // here (visible but inert) — never hidden. Computed at render time, NOT
    // captured in onAppear: a paged TabView pre-builds neighbor pages and
    // fires their appearance early — a stored snapshot would freeze the
    // pre-answer state and never reflect the go-to picks the user just made.
    private var lockedBeers: Set<String> {
        Set(TastePreferences.savedKnownBeers).intersection(Set(onboardingBeerOptions))
    }
    private var lockedStyles: Set<BeerStyle> {
        Set(TastePreferences.current.goToStyles.compactMap { BeerStyle(rawValue: $0) })
    }

    private var title: String {
        copyVariant == "alt" ? "Any hard passes?" : "What do you always walk past?"
    }

    private var subtitle: String {
        copyVariant == "alt"
            ? "We'll steer you clear. No judgment."
            : "Tap what's never coming home with you."
    }

    /// "Got it — steering you clear of stouts, sours." Style rawValues from
    /// the resolver, rendered mid-sentence: pluralized display labels,
    /// lowercased unless the singular is an acronym ("IPAs" stays "IPAs").
    private var echoLine: String {
        let names = echoedAvoidStyles.map { raw -> String in
            guard let style = BeerStyle(rawValue: raw) else { return raw.lowercased() }
            let label = styleChipLabel(style)
            let singular = String(label.dropLast())
            return singular == singular.uppercased() ? label : label.lowercased()
        }
        return "Got it — steering you clear of \(names.joined(separator: ", "))."
    }

    var body: some View {
        PickerPageScaffold(
            title: title,
            subtitle: subtitle,
            primaryTitle: isLast ? "See my picks" : "Next →",
            primaryAccessibilityID: "onboardingStayAwayNext",
            primaryAction: advance,
            quietTitle: "Nothing's off the table",
            quietAccessibilityID: "onboardingStayAwaySkip",
            // Skip never writes — advancing/completing without a pick must
            // leave saved avoid data untouched.
            quietAction: onAdvance
        ) {
            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Styles")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                // Wider cells than the beer grid: the exemplar anchor line
                // ("like Guinness") must fit on one line.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: SipSpacing.s)],
                    alignment: .leading,
                    spacing: SipSpacing.s
                ) {
                    ForEach(onboardingStyleChips, id: \.self) { style in
                        ChipButton(
                            label: styleChipLabel(style),
                            isSelected: selectedAvoidStyles.contains(style),
                            lockedCaption: lockedStyles.contains(style) ? "go-to" : nil,
                            anchorCaption: styleChipAnchor(style)
                        ) {
                            toggleStyle(style)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Beers")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: SipSpacing.s)],
                    alignment: .leading,
                    spacing: SipSpacing.s
                ) {
                    ForEach(onboardingBeerOptions, id: \.self) { beer in
                        ChipButton(
                            label: beer,
                            isSelected: selectedAvoidBeers.contains(beer),
                            lockedCaption: lockedBeers.contains(beer) ? "go-to" : nil
                        ) {
                            toggleBeer(beer)
                        }
                    }
                }
            }

            // Inline echo of the style generalization the picks resolve to
            // ("Guinness" → stouts) — confirms the avoid registered at the
            // category level and pre-teaches the verdict's "you said so"
            // voice. Appears the moment resolution lands, hides when the
            // last pick is cleared.
            if !echoedAvoidStyles.isEmpty {
                Text(echoLine)
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textSecondary)
                    .accessibilityIdentifier("avoidEchoLine")
                    .transition(.opacity)
            }
        }
        .onAppear {
            restoreSavedSelections()
        }
    }

    /// Restore prior picks (guard-if-empty per field). Saved avoid picks are
    /// a mixed list: style rawValues split back into style chips, known beer
    /// options back into beer chips.
    private func restoreSavedSelections() {
        let savedPicks = TastePreferences.savedAvoidBeers
        if selectedAvoidStyles.isEmpty {
            selectedAvoidStyles = Set(savedPicks.compactMap { BeerStyle(rawValue: $0) })
        }
        if selectedAvoidBeers.isEmpty {
            selectedAvoidBeers = Set(savedPicks).intersection(Set(onboardingBeerOptions))
        }
        if echoedAvoidStyles.isEmpty {
            // Saved picks were already resolved at save time — echo them
            // directly instead of re-running resolution.
            echoedAvoidStyles = TastePreferences.current.avoidStyles
        }
    }

    private func toggleStyle(_ style: BeerStyle) {
        if selectedAvoidStyles.contains(style) {
            selectedAvoidStyles.remove(style)
        } else {
            selectedAvoidStyles.insert(style)
        }
        // Write-through on every tap.
        persistAvoidSelections()
    }

    private func toggleBeer(_ beer: String) {
        if selectedAvoidBeers.contains(beer) {
            selectedAvoidBeers.remove(beer)
        } else {
            selectedAvoidBeers.insert(beer)
        }
        // Write-through on every tap.
        persistAvoidSelections()
    }

    /// Persist the raw avoid picks AND the styles they resolve to. Style
    /// chips resolve directly; beer names go through the same catalog+
    /// inference fusion the scan path uses ("avoid Guinness" must penalize
    /// stouts). Off-main with a generation guard — the LATEST tap's snapshot
    /// wins.
    private func persistAvoidSelections() {
        avoidGeneration += 1
        let generation = avoidGeneration
        let picks = selectedAvoidBeers.sorted() + selectedAvoidStyles.map(\.rawValue).sorted()

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                var resolved: Set<String> = []
                for pick in picks {
                    if let direct = BeerStyle.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(pick) == .orderedSame }) {
                        resolved.insert(direct.rawValue)
                    } else if let style = TastePreferences.styleForOnboardingBeer(pick)
                        ?? BeerResolver.resolve(recognizedText: pick, using: BundledCatalog.shared).style {
                        resolved.insert(style.rawValue)
                    }
                }
                return resolved.sorted()
            }.value
            guard generation == avoidGeneration else { return } // stale snapshot
            // Update the inline echo BEFORE the preview gate: the echo is
            // display-only, so Lab previews get it too.
            await MainActor.run {
                withAnimation(.snappy(duration: 0.25)) {
                    echoedAvoidStyles = styles
                }
            }
            guard !isPreview else { return } // Lab preview never touches taste data
            TastePreferences.saveAvoidBeers(picks, avoidStyles: styles)
        }
    }

    private func advance() {
        persistAvoidSelections()
        onAdvance()
    }
}

// MARK: - Taste Quiz Page

private struct TasteQuizPage: View {
    /// Q2 ("How adventurous?") — control only; the new flows ask it on the
    /// go-to page instead.
    let includeAdventure: Bool
    /// Q3 ("Anything you hate?") — control only; the new flows have a whole
    /// stay-away page, so the question would overlap.
    let includeDislikes: Bool
    /// Lab preview: answers stay interactive but nothing persists.
    let isPreview: Bool
    /// The quiz is always the flow's final page: submit and skip both finish.
    let onFinish: () -> Void

    @State private var selectedVibe: String? = nil
    @State private var selectedAdventure: String? = nil
    @State private var selectedDislikes: Set<String> = []

    // Single-sourced from TastePreferences so Settings' editor offers the
    // exact same answer strings (drift would corrupt saved answers).
    private let vibeOptions = TastePreferences.vibeOptions
    private let adventureOptions = TastePreferences.adventureOptions
    private let dislikeOptions = TastePreferences.dislikeOptions

    private var hasRequiredSelections: Bool {
        includeAdventure
            ? selectedVibe != nil && selectedAdventure != nil
            : selectedVibe != nil
    }

    var body: some View {
        PickerPageScaffold(
            title: "Last one — dial in your taste",
            subtitle: "Ten seconds. Way better picks.",
            primaryTitle: "See my picks",
            primaryAccessibilityID: "onboardingQuizSubmit",
            primaryDisabled: !hasRequiredSelections,
            primaryAction: saveAndFinish,
            quietTitle: "Skip — you can tune this later",
            quietAccessibilityID: "onboardingQuizSkip",
            // Skip must NOT persist: it only ends onboarding. Real answers
            // were already written through by the onChange handlers below.
            quietAction: onFinish
        ) {
            // Q1: Vibe
            QuizQuestion(
                question: "Pick your vibe",
                options: vibeOptions,
                multiSelect: false,
                selectedSingle: $selectedVibe,
                selectedMulti: .constant([])
            )

            // Q2: Adventure (control only)
            if includeAdventure {
                QuizQuestion(
                    question: "How adventurous?",
                    options: adventureOptions,
                    multiSelect: false,
                    selectedSingle: $selectedAdventure,
                    selectedMulti: .constant([])
                )
            }

            // Q3: Dislikes (optional; control only)
            if includeDislikes {
                QuizQuestion(
                    question: "Anything you hate?",
                    questionSuffix: "(optional)",
                    options: dislikeOptions,
                    multiSelect: true,
                    selectedSingle: .constant(nil),
                    selectedMulti: $selectedDislikes
                )
            }
        }
        .onAppear {
            restoreSavedAnswers()
        }
        .onChange(of: selectedVibe) { _, _ in persistAnswers() }
        .onChange(of: selectedAdventure) { _, _ in persistAnswers() }
        .onChange(of: selectedDislikes) { _, _ in persistAnswers() }
    }

    /// Restore any previously saved answers so replaying onboarding (or a
    /// reinstall with iCloud KVS answers) starts from what the user already
    /// said — and so Skip can never erase real answers with blanks.
    private func restoreSavedAnswers() {
        let saved = TastePreferences.current
        if selectedVibe == nil, !saved.vibe.isEmpty { selectedVibe = saved.vibe }
        if selectedAdventure == nil, !saved.adventure.isEmpty { selectedAdventure = saved.adventure }
        if selectedDislikes.isEmpty, !saved.dislikes.isEmpty { selectedDislikes = Set(saved.dislikes) }
    }

    /// Write-through on every selection change: quiz answers survive swiping
    /// away mid-quiz, backgrounding, or skipping the final button.
    /// Questions this variant doesn't ask are sourced from the saved profile
    /// at write time — the vibe-only quiz must never blank the adventure the
    /// go-to page just saved (save() writes all three keys locally).
    private func persistAnswers() {
        guard !isPreview else { return } // Lab preview never touches taste data
        let saved = TastePreferences.current
        let adventure = includeAdventure
            ? (selectedAdventure ?? "")
            : (selectedAdventure ?? saved.adventure)
        let dislikes = includeDislikes
            ? selectedDislikes.joined(separator: ",")
            : saved.dislikes.joined(separator: ",")
        TastePreferences.save(
            vibe: selectedVibe ?? "",
            adventure: adventure,
            dislikes: dislikes
        )
    }

    private func saveAndFinish() {
        persistAnswers()
        onFinish()
    }
}

// MARK: - Quiz Question

private struct QuizQuestion: View {
    let question: String
    var questionSuffix: String? = nil
    let options: [String]
    let multiSelect: Bool
    @Binding var selectedSingle: String?
    @Binding var selectedMulti: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            HStack(spacing: SipSpacing.xs) {
                Text(question)
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                if let suffix = questionSuffix {
                    Text(suffix)
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
            }
            ChipGrid(
                options: options,
                multiSelect: multiSelect,
                selectedSingle: $selectedSingle,
                selectedMulti: $selectedMulti
            )
        }
    }
}

// MARK: - Chip Grid

private struct ChipGrid: View {
    let options: [String]
    let multiSelect: Bool
    @Binding var selectedSingle: String?
    @Binding var selectedMulti: Set<String>

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: SipSpacing.s)],
            alignment: .leading,
            spacing: SipSpacing.s
        ) {
            ForEach(options, id: \.self) { option in
                ChipButton(
                    label: option,
                    isSelected: multiSelect
                        ? selectedMulti.contains(option)
                        : selectedSingle == option
                ) {
                    if multiSelect {
                        if selectedMulti.contains(option) {
                            selectedMulti.remove(option)
                        } else {
                            selectedMulti.insert(option)
                        }
                    } else {
                        selectedSingle = option
                    }
                }
            }
        }
    }
}

// MARK: - Chip Button (thin wrapper over the shared SipChipStyle)
// Internal (not file-private): Settings' TastePreferencesEditorView renders
// the same chips — selected, locked, and captioned — for go-to/stay-away edits.

struct ChipButton: View {
    let label: String
    let isSelected: Bool
    /// Non-nil = locked: the chip is claimed by the opposite picker page.
    /// Locked chips dim, show the caption, and ignore taps — visible but
    /// inert, never hidden.
    var lockedCaption: String? = nil
    /// Optional exemplar anchor ("like Guinness") rendered as a second,
    /// smaller line — style chips carry a concrete beer so answering never
    /// requires beer vocabulary. Display only. While locked, the lock
    /// caption owns the second line and the anchor is suppressed.
    var anchorCaption: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            if lockedCaption == nil {
                action()
            }
        }) {
            if let caption = lockedCaption ?? anchorCaption {
                VStack(spacing: 2) {
                    Text(label)
                    Text(caption)
                        .font(SipTypography.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text(label)
            }
        }
        .buttonStyle(SipChipStyle(isSelected: isSelected && lockedCaption == nil))
        .opacity(lockedCaption == nil ? 1 : 0.4)
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .preferredColorScheme(.dark)
    }
}
