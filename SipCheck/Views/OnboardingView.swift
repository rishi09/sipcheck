import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            onboardingPage(
                icon: "mug.fill",
                title: "Never Waste a Sip Again",
                description: "Stood in the beer aisle not sure what to grab? SipCheck tells you in seconds.",
                tag: 0,
                // Beer-native amber hero (matches the Check idle motif) — the
                // age gate already owns the teal mug; don't repeat it here.
                iconStyle: AnyShapeStyle(StyleGradient.gradient(for: "IPA"))
            )
            onboardingPage(
                icon: "camera.fill",
                title: "Scan a Label, Get a Verdict",
                description: "TRY IT. SKIP IT. YOUR CALL. — based on what you like, not what beer nerds think.",
                tag: 1
            )
            onboardingPage(
                icon: "sparkles",
                title: "The More You Log, the Better It Gets",
                description: "Every beer you rate teaches SipCheck your taste. Recommendations get sharper every week.",
                tag: 2
            )
            beerPickerPage(tag: 3)
            tasteQuizPage(tag: 4)
        }
        // Pages 3–4 carry their own CTA blocks — hide the system dots there so
        // buttons never fight the page indicator for the same bottom band.
        .tabViewStyle(.page(indexDisplayMode: currentPage >= 3 ? .never : .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(SipColors.background.ignoresSafeArea())
    }

    private func onboardingPage(
        icon: String,
        title: String,
        description: String,
        tag: Int,
        iconStyle: AnyShapeStyle = AnyShapeStyle(SipColors.accent)
    ) -> some View {
        StoryPage(
            icon: icon,
            title: title,
            description: description,
            tag: tag,
            currentPage: $currentPage,
            iconStyle: iconStyle
        )
    }

    private func beerPickerPage(tag: Int) -> some View {
        BeerPickerPage(tag: tag, currentPage: $currentPage)
    }

    private func tasteQuizPage(tag: Int) -> some View {
        TasteQuizPage(tag: tag, hasCompletedOnboarding: $hasCompletedOnboarding)
    }
}

// MARK: - Story Page

private struct StoryPage: View {
    let icon: String
    let title: String
    let description: String
    let tag: Int
    @Binding var currentPage: Int
    var iconStyle: AnyShapeStyle = AnyShapeStyle(SipColors.accent)

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 80

    var body: some View {
        VStack(spacing: SipSpacing.xl) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: heroIconSize))
                .foregroundStyle(iconStyle)
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
            Button(action: advance) {
                Text("Continue")
            }
            .buttonStyle(SipPrimaryButtonStyle())
            .padding(.horizontal, SipSpacing.xl)
            // Clear the system page dots below the CTA.
            .padding(.bottom, 56)
        }
        .tag(tag)
    }

    private func advance() {
        withAnimation(.smooth) {
            currentPage = tag + 1
        }
    }
}

// MARK: - Beer Picker Page

private struct BeerPickerPage: View {
    let tag: Int
    @Binding var currentPage: Int

    @State private var selectedBeers: Set<String> = []
    @State private var showCoronaEgg = false
    /// Monotonic guard: only the newest persistSelections snapshot may write.
    @State private var persistGeneration = 0

    private let beerOptions = [
        "Modelo", "Corona", "Heineken", "Blue Moon",
        "Sam Adams", "Guinness", "Sierra Nevada", "Lagunitas",
        "Hazy Little Thing", "Coors Light", "Bud Light", "Stella Artois",
        "Allagash White", "Dogfish Head", "Stone IPA", "Goose Island"
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: SipSpacing.xl) {
                    // Header
                    VStack(alignment: .leading, spacing: SipSpacing.s) {
                        Text("Beers you've had before?")
                            .font(SipTypography.title)
                            .foregroundColor(SipColors.textPrimary)
                        Text("Tap any you've tried. We'll use it to calibrate your taste.")
                            .font(SipTypography.subhead)
                            .foregroundColor(SipColors.textSecondary)
                    }
                    .padding(.top, SipSpacing.xl)

                    // Beer chip grid
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: SipSpacing.s)],
                        alignment: .leading,
                        spacing: SipSpacing.s
                    ) {
                        ForEach(beerOptions, id: \.self) { beer in
                            ChipButton(
                                label: beer,
                                isSelected: selectedBeers.contains(beer)
                            ) {
                                toggleBeer(beer)
                            }
                        }
                    }

                    // Spacer so content clears the fixed buttons
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, SipSpacing.xl)
            }

            // Fixed bottom area: toast + CTA + Skip
            VStack(spacing: 0) {
                // Corona easter egg toast
                if showCoronaEgg {
                    HStack(spacing: SipSpacing.s) {
                        Text("🏎️")
                            .font(SipTypography.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\"One quarter mile at a time.\"")
                                .font(SipTypography.subhead)
                                .foregroundColor(SipColors.textPrimary)
                            Text("— Dominic Toretto")
                                .font(SipTypography.caption)
                                .foregroundColor(SipColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.vertical, SipSpacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: SipRadius.card, style: .continuous)
                            .fill(SipColors.surfaceElevated)
                            .shadow(color: SipColors.background.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.bottom, SipSpacing.m)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 20)),
                            removal: .opacity.combined(with: .offset(y: 20))
                        )
                    )
                }

                // CTA hierarchy: one primary, one quiet skip.
                VStack(spacing: SipSpacing.m) {
                    Button(action: advance) {
                        Text("Next →")
                    }
                    .buttonStyle(SipPrimaryButtonStyle())

                    Button(action: advance) {
                        Text("Skip")
                    }
                    .buttonStyle(SipQuietButtonStyle())
                }
                .padding(.horizontal, SipSpacing.xl)
                .padding(.top, SipSpacing.s)
                // System dots are hidden on this page; clear the home indicator.
                .padding(.bottom, SipSpacing.xl)
                .background(
                    // Subtle gradient to blend with scroll content
                    LinearGradient(
                        gradient: Gradient(colors: [SipColors.background.opacity(0), SipColors.background]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .tag(tag)
        .onAppear {
            // Replay/reinstall: restore prior picks so the first new tap's
            // write-through doesn't overwrite a multi-beer selection (and its
            // synced seed styles) with a single beer.
            if selectedBeers.isEmpty {
                selectedBeers = Set(TastePreferences.savedKnownBeers).intersection(Set(beerOptions))
            }
        }
    }

    private func toggleBeer(_ beer: String) {
        let wasSelected = selectedBeers.contains(beer)
        if wasSelected {
            selectedBeers.remove(beer)
        } else {
            selectedBeers.insert(beer)
            if beer == "Corona" {
                withAnimation(.snappy(duration: 0.25)) {
                    showCoronaEgg = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.snappy(duration: 0.25)) {
                        showCoronaEgg = false
                    }
                }
            }
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
        persistGeneration += 1
        let generation = persistGeneration
        let beers = Array(selectedBeers)

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                // Same catalog+inference fusion the scan path uses, so the
                // seed style for a beer matches what scanning it would resolve.
                Array(Set(beers.compactMap {
                    BeerResolver.resolve(recognizedText: $0, using: BundledCatalog.shared).style?.rawValue
                })).sorted()
            }.value
            guard generation == persistGeneration else { return } // stale snapshot
            TastePreferences.saveKnownBeers(beers, seedStyles: styles)
        }
    }

    private func advance() {
        persistSelections()
        withAnimation(.smooth) {
            currentPage = 4
        }
    }
}

// MARK: - Taste Quiz Page

private struct TasteQuizPage: View {
    let tag: Int
    @Binding var hasCompletedOnboarding: Bool

    @State private var selectedVibe: String? = nil
    @State private var selectedAdventure: String? = nil
    @State private var selectedDislikes: Set<String> = []

    // Single-sourced from TastePreferences so Settings' editor offers the
    // exact same answer strings (drift would corrupt saved answers).
    private let vibeOptions = TastePreferences.vibeOptions
    private let adventureOptions = TastePreferences.adventureOptions
    private let dislikeOptions = TastePreferences.dislikeOptions

    private var hasRequiredSelections: Bool {
        selectedVibe != nil && selectedAdventure != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                VStack(alignment: .leading, spacing: SipSpacing.s) {
                    Text("Quick — what do you like?")
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Takes 10 seconds. Makes recommendations way better.")
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
                .padding(.top, SipSpacing.xl)

                // Q1: Vibe
                QuizQuestion(
                    question: "Pick your vibe",
                    options: vibeOptions,
                    multiSelect: false,
                    selectedSingle: $selectedVibe,
                    selectedMulti: .constant([])
                )

                // Q2: Adventure
                QuizQuestion(
                    question: "How adventurous?",
                    options: adventureOptions,
                    multiSelect: false,
                    selectedSingle: $selectedAdventure,
                    selectedMulti: .constant([])
                )

                // Q3: Dislikes (optional)
                QuizQuestion(
                    question: "Anything you hate?",
                    questionSuffix: "(optional)",
                    options: dislikeOptions,
                    multiSelect: true,
                    selectedSingle: .constant(nil),
                    selectedMulti: $selectedDislikes
                )

                // CTA — a clear primary submit plus a distinct quiet Skip.
                VStack(spacing: SipSpacing.m) {
                    Button(action: saveAndContinue) {
                        Text("See My Picks")
                    }
                    .buttonStyle(SipPrimaryButtonStyle())
                    .disabled(!hasRequiredSelections)

                    // Skip leaves saved prefs untouched — answered-state
                    // write-through below already persists real answers.
                    Button(action: skip) {
                        Text("Skip — you can tune this later")
                    }
                    .buttonStyle(SipQuietButtonStyle())
                }
                .padding(.top, SipSpacing.s)
                // System dots are hidden on this page; modest bottom clearance.
                .padding(.bottom, SipSpacing.xl)
            }
            .padding(.horizontal, SipSpacing.xl)
        }
        .tag(tag)
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
    private func persistAnswers() {
        TastePreferences.save(
            vibe: selectedVibe ?? "",
            adventure: selectedAdventure ?? "",
            dislikes: selectedDislikes.joined(separator: ",")
        )
    }

    private func saveAndContinue() {
        persistAnswers()
        hasCompletedOnboarding = true
    }

    /// Skip must NOT persist: it only ends onboarding. Real answers were
    /// already written through by the onChange handlers above.
    private func skip() {
        hasCompletedOnboarding = true
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

private struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(SipChipStyle(isSelected: isSelected))
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .preferredColorScheme(.dark)
    }
}
