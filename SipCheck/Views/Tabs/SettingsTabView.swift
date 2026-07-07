import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var journalStore: JournalStore

    @Environment(\.dismiss) private var dismiss

    @AppStorage("preferredScanProvider") private var preferredScanProvider: String = "auto"
    @AppStorage("followUpNotificationsEnabled") private var followUpNotificationsEnabled: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = true
    @AppStorage("hasConfirmedAge") private var hasConfirmedAge: Bool = true

    // Onboarding Lab variant knobs — key strings are the WO-A/WO-D contract;
    // OnboardingView reads these same @AppStorage keys live.
    @AppStorage("onboardingFlowVariant") private var flowVariant: String = "goToStayAway"
    @AppStorage("onboardingCopyVariantPage1") private var copyVariantPage1: String = "A"
    @AppStorage("onboardingScanVignette") private var scanVignette: String = "full"
    @AppStorage("onboardingPickerCopyVariant") private var pickerCopyVariant: String = "primary"

    @State private var showOnboardingPreview = false
    @State private var showResetOnboardingAlert = false
    @State private var showClearDataAlert = false
    @State private var showingTasteEditor = false
    /// Identifiable wrapper so the export uses sheet(item:) — isPresented +
    /// if-let raced the URL write and could present a blank share sheet.
    private struct ExportItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    @State private var exportItem: ExportItem?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Scanning (debug-only: provider choice is a dev knob, not a user setting)
                #if DEBUG
                Section {
                    Picker("AI Provider", selection: $preferredScanProvider) {
                        Text("Auto (Recommended)").tag("auto")
                        Text("OpenAI Vision only").tag("openai")
                    }
                    Text("Auto uses fast text recognition first, falling back to AI vision.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Scanning")
                }
                #endif

                // MARK: - Taste
                Section {
                    Button("Edit taste preferences") {
                        showingTasteEditor = true
                    }
                } header: {
                    Text("Taste")
                } footer: {
                    Text("Tune your go-tos, stay-aways, and quiz answers — verdicts follow instantly.")
                }

                // MARK: - Onboarding Lab (founder feedback loop — remove before public App Store release)
                Section {
                    Picker("Flow", selection: $flowVariant) {
                        Text("Go-to & stay-away").tag("goToStayAway")
                        Text("Go-to & stay-away + vibe question").tag("goToStayAwayPlusVibe")
                        Text("Classic (had-before + quiz)").tag("control")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("labFlowVariantPicker")

                    // Labels ARE the headlines so the founder previews the words
                    // before committing to a walkthrough.
                    Picker("First screen", selection: $copyVariantPage1) {
                        Text("Buy better beer.").tag("A")
                        Text("Stop guessing. Buy better beer.").tag("B")
                        Text("Never waste a sip again").tag("C")
                        // D shares A's headline — the label carries the body
                        // line too so the variants stay distinguishable.
                        Text("Buy better beer. — Picked for your taste, not the crowd's.").tag("D")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("labPage1CopyPicker")

                    Picker("Scan screen", selection: $scanVignette) {
                        Text("Full vignette").tag("full")
                        Text("Minimal").tag("minimal")
                        Text("Icon only").tag("icon")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("labScanVignettePicker")

                    Picker("Picker wording", selection: $pickerCopyVariant) {
                        Text("What's your go-to?").tag("primary")
                        Text("What's in your fridge right now?").tag("alt")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("labPickerCopyPicker")

                    Button("Preview Onboarding") {
                        showOnboardingPreview = true
                    }
                    .accessibilityIdentifier("labPreviewOnboardingButton")
                } header: {
                    Text("Onboarding Lab")
                } footer: {
                    Text("Pick variants, tap Preview, tell Claude which one. Preview never touches your taste data.")
                }

                // MARK: - Notifications
                Section {
                    Toggle(isOn: $followUpNotificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Follow-up reminders")
                            Text("We'll check in a day or two after you save one")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Notifications")
                }

                // MARK: - Export
                Section {
                    Button {
                        exportAsCSV()
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    Button {
                        exportAsJSON()
                    } label: {
                        Label("Export as JSON", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Export my data")
                }

                // MARK: - Account / Data
                Section {
                    Button("Replay Onboarding") {
                        showResetOnboardingAlert = true
                    }
                    .alert("Replay Onboarding?", isPresented: $showResetOnboardingAlert) {
                        Button("Replay", role: .destructive) {
                            // Dismiss this sheet first; if we flip the flags while the
                            // sheet is up, the RootView swap happens underneath it and
                            // never becomes visible. Flip them after dismissal settles.
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                hasConfirmedAge = false
                                hasCompletedOnboarding = false
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Takes you back through the age gate and intro screens right now.")
                    }

                    Button("Clear All Data") {
                        showClearDataAlert = true
                    }
                    .foregroundColor(SipColors.destructive)
                    .alert("Clear All Data?", isPresented: $showClearDataAlert) {
                        Button("Delete Everything", role: .destructive) {
                            let allIndices = IndexSet(drinkStore.drinks.indices)
                            drinkStore.deleteDrinks(at: allIndices, from: drinkStore.drinks)
                            scanStore.deleteAllScans()
                            journalStore.deleteAllEntries()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all your beers and scans. This cannot be undone.")
                    }
                    // Available in TestFlight builds too so testers can populate
                    // sample data (which then syncs to iCloud). Remove before the
                    // public App Store release.
                    Button("Seed Sample Data") {
                        drinkStore.seedSampleData()
                        scanStore.seedSampleData()
                        journalStore.seedSampleData()
                    }
                } header: {
                    Text("Account / Data")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    Link("Privacy Policy", destination: URL(string: "https://rishi09.github.io/sipcheck/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://rishi09.github.io/sipcheck/terms")!)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingTasteEditor) {
                TastePreferencesEditorView()
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            // Onboarding Lab preview: fullScreenCover so the flow renders at real
            // geometry. onFinish dismisses the cover instead of flipping
            // hasCompletedOnboarding, so the preview never mutates completion
            // flags or taste data. "Replay Onboarding" above remains the
            // full-reset path.
            .fullScreenCover(isPresented: $showOnboardingPreview) {
                OnboardingView(onFinish: { showOnboardingPreview = false })
                    .preferredColorScheme(.dark)
            }
        }
        .accessibilityIdentifier("settingsTab")
    }

    // MARK: - Export (relocated from StatsView; WO-8 deletes the originals)

    private func exportAsJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(drinkStore.drinks) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.json")
        try? data.write(to: tempURL)
        exportItem = ExportItem(url: tempURL)
    }

    private func exportAsCSV() {
        var csv = "Name,Brand,Style,Rating,ABV,Type,Notes,Date\n"
        for drink in drinkStore.drinks {
            let name = drink.name.replacingOccurrences(of: ",", with: ";")
            let brand = drink.brand.replacingOccurrences(of: ",", with: ";")
            let notes = (drink.notes ?? "").replacingOccurrences(of: ",", with: ";")
            let abv = drink.abv.map { String(format: "%.1f", $0) } ?? ""
            let date = drink.dateAdded.formatted(.iso8601)
            csv += "\(name),\(brand),\(drink.style),\(drink.rating.displayName),\(abv),\(drink.drinkType.displayName),\(notes),\(date)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportItem = ExportItem(url: tempURL)
    }
}

// MARK: - Taste Preferences Editor
// Deep-links to the FULL taste signal set — go-to picks, stay-away picks, and
// the quiz — with no age-gate or onboarding reset. The default (goToStayAway)
// flow never asks the quiz, so without the picker grids its users would have
// no way to revise their primary signals short of replaying onboarding.
// (OnboardingView's pages are file-private, so the layouts are mirrored here
// against the same TastePreferences store; the option pools, chip labels, and
// ChipButton are single-sourced from OnboardingView, and the quiz option
// strings from TastePreferences.)

private struct TastePreferencesEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVibe: String? = nil
    @State private var selectedAdventure: String? = nil
    @State private var selectedDislikes: Set<String> = []

    // Go-to / stay-away picks (the default flow's primary signals).
    @State private var goToBeers: Set<String> = []
    @State private var goToStyles: Set<BeerStyle> = []
    @State private var avoidBeers: Set<String> = []
    @State private var avoidStyles: Set<BeerStyle> = []
    /// Monotonic guards, one per save channel (same pattern as the onboarding
    /// pages): only the newest persist snapshot may write.
    @State private var goToGeneration = 0
    @State private var avoidGeneration = 0

    // Single-sourced from TastePreferences — must be the exact strings the
    // onboarding quiz offers, since both write the same saved-answer keys.
    private let vibeOptions = TastePreferences.vibeOptions
    private let adventureOptions = TastePreferences.adventureOptions
    private let dislikeOptions = TastePreferences.dislikeOptions

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Same picks and quiz as onboarding — change anything, verdicts update instantly.")
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                        .padding(.top, SipSpacing.s)

                    // Go-to / stay-away grids first: they're the default
                    // flow's primary taste signals. Locks are live — a chip
                    // claimed on one side is inert (dimmed + captioned) on
                    // the other, mirroring the onboarding cross-exclusion.
                    VStack(alignment: .leading, spacing: SipSpacing.m) {
                        Text("Your go-tos")
                            .font(SipTypography.headline)
                            .foregroundColor(SipColors.textPrimary)
                        picksGrid(
                            styleSelected: { goToStyles.contains($0) },
                            styleLocked: { avoidStyles.contains($0) ? "stay-away" : nil },
                            onTapStyle: toggleGoToStyle,
                            beerSelected: { goToBeers.contains($0) },
                            beerLocked: { avoidBeers.contains($0) ? "stay-away" : nil },
                            onTapBeer: toggleGoToBeer
                        )
                    }

                    VStack(alignment: .leading, spacing: SipSpacing.m) {
                        Text("Your stay-aways")
                            .font(SipTypography.headline)
                            .foregroundColor(SipColors.textPrimary)
                        picksGrid(
                            styleSelected: { avoidStyles.contains($0) },
                            styleLocked: { goToStyles.contains($0) ? "go-to" : nil },
                            onTapStyle: toggleAvoidStyle,
                            beerSelected: { avoidBeers.contains($0) },
                            beerLocked: { goToBeers.contains($0) ? "go-to" : nil },
                            onTapBeer: toggleAvoidBeer
                        )
                    }

                    quizQuestion(
                        question: "Pick your vibe",
                        options: vibeOptions
                    ) { option in
                        selectedVibe == option
                    } onTap: { option in
                        selectedVibe = option
                    }

                    quizQuestion(
                        question: "How adventurous?",
                        options: adventureOptions
                    ) { option in
                        selectedAdventure == option
                    } onTap: { option in
                        selectedAdventure = option
                    }

                    quizQuestion(
                        question: "Anything you hate?",
                        questionSuffix: "(optional)",
                        options: dislikeOptions
                    ) { option in
                        selectedDislikes.contains(option)
                    } onTap: { option in
                        if selectedDislikes.contains(option) {
                            selectedDislikes.remove(option)
                        } else {
                            selectedDislikes.insert(option)
                        }
                    }

                    Button(action: { dismiss() }) {
                        Text("Done")
                    }
                    .buttonStyle(SipPrimaryButtonStyle())
                    .padding(.top, SipSpacing.s)
                    .padding(.bottom, SipSpacing.xl)
                }
                .padding(.horizontal, SipSpacing.xl)
            }
            .background(SipColors.background.ignoresSafeArea())
            .navigationTitle("Taste Preferences")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            restoreSavedAnswers()
        }
        .onChange(of: selectedVibe) { _, _ in persistAnswers() }
        .onChange(of: selectedAdventure) { _, _ in persistAnswers() }
        .onChange(of: selectedDislikes) { _, _ in persistAnswers() }
    }

    private func quizQuestion(
        question: String,
        questionSuffix: String? = nil,
        options: [String],
        isSelected: @escaping (String) -> Bool,
        onTap: @escaping (String) -> Void
    ) -> some View {
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

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: SipSpacing.s)],
                alignment: .leading,
                spacing: SipSpacing.s
            ) {
                ForEach(options, id: \.self) { option in
                    Button(action: { onTap(option) }) {
                        Text(option)
                    }
                    .buttonStyle(SipChipStyle(isSelected: isSelected(option)))
                }
            }
        }
    }

    /// Two adaptive grids per section: brand-anchored style chips (wider
    /// cells so the exemplar line fits, mirroring the onboarding pickers)
    /// followed by the shared 16-beer pool — the exact pools the onboarding
    /// pickers offer, so edits restore identically on a replay.
    private func picksGrid(
        styleSelected: @escaping (BeerStyle) -> Bool,
        styleLocked: @escaping (BeerStyle) -> String?,
        onTapStyle: @escaping (BeerStyle) -> Void,
        beerSelected: @escaping (String) -> Bool,
        beerLocked: @escaping (String) -> String?,
        onTapBeer: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: SipSpacing.s) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: SipSpacing.s)],
                alignment: .leading,
                spacing: SipSpacing.s
            ) {
                ForEach(onboardingStyleChips, id: \.self) { style in
                    ChipButton(
                        label: styleChipLabel(style),
                        isSelected: styleSelected(style),
                        lockedCaption: styleLocked(style),
                        anchorCaption: styleChipAnchor(style)
                    ) {
                        onTapStyle(style)
                    }
                }
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: SipSpacing.s)],
                alignment: .leading,
                spacing: SipSpacing.s
            ) {
                ForEach(onboardingBeerOptions, id: \.self) { beer in
                    ChipButton(
                        label: beer,
                        isSelected: beerSelected(beer),
                        lockedCaption: beerLocked(beer)
                    ) {
                        onTapBeer(beer)
                    }
                }
            }
        }
    }

    // MARK: Go-to / stay-away tap handlers (write-through on every tap,
    // matching the onboarding pages — swiping the sheet away must not
    // discard edits)

    private func toggleGoToStyle(_ style: BeerStyle) {
        if goToStyles.contains(style) { goToStyles.remove(style) } else { goToStyles.insert(style) }
        persistGoTo()
    }

    private func toggleGoToBeer(_ beer: String) {
        if goToBeers.contains(beer) { goToBeers.remove(beer) } else { goToBeers.insert(beer) }
        persistGoTo()
    }

    private func toggleAvoidStyle(_ style: BeerStyle) {
        if avoidStyles.contains(style) { avoidStyles.remove(style) } else { avoidStyles.insert(style) }
        persistAvoid()
    }

    private func toggleAvoidBeer(_ beer: String) {
        if avoidBeers.contains(beer) { avoidBeers.remove(beer) } else { avoidBeers.insert(beer) }
        persistAvoid()
    }

    /// Mirror of GoToPickerPage.persistSelections: persist the picks, the
    /// explicit style chips, AND the styles the beer picks resolve to.
    /// Resolution runs off-main (catalog decode); the generation guard makes
    /// the LATEST tap's snapshot win.
    private func persistGoTo() {
        goToGeneration += 1
        let generation = goToGeneration
        let beers = Array(goToBeers)
        // Snapshot the chips BEFORE the async hop — the save writes all three
        // keys, so a stale chip set must never ride along with a fresh
        // beer resolution.
        let styleChips = goToStyles.map(\.rawValue).sorted()

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                Array(Set(beers.compactMap {
                    BeerResolver.resolve(recognizedText: $0, using: BundledCatalog.shared).style?.rawValue
                })).sorted()
            }.value
            guard generation == goToGeneration else { return } // stale snapshot
            TastePreferences.saveGoTo(beers: beers, styleChips: styleChips, seedStyles: styles)
        }
    }

    /// Mirror of StayAwayPickerPage.persistAvoidSelections: raw picks (mixed
    /// beer names + style rawValues) plus the styles they resolve to — the
    /// scorer's avoid channel consumes the resolved styles.
    private func persistAvoid() {
        avoidGeneration += 1
        let generation = avoidGeneration
        let picks = avoidBeers.sorted() + avoidStyles.map(\.rawValue).sorted()

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                var resolved: Set<String> = []
                for pick in picks {
                    if let direct = BeerStyle.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(pick) == .orderedSame }) {
                        resolved.insert(direct.rawValue)
                    } else if let style = BeerResolver.resolve(recognizedText: pick, using: BundledCatalog.shared).style {
                        resolved.insert(style.rawValue)
                    }
                }
                return resolved.sorted()
            }.value
            guard generation == avoidGeneration else { return } // stale snapshot
            TastePreferences.saveAvoidBeers(picks, avoidStyles: styles)
        }
    }

    /// Mirror of the onboarding pages' restores: start from what the user
    /// already said (guard-if-empty per field) so opening the editor never
    /// blanks real answers, and the first tap's write-through never
    /// overwrites a fuller saved set.
    private func restoreSavedAnswers() {
        let saved = TastePreferences.current
        if selectedVibe == nil, !saved.vibe.isEmpty { selectedVibe = saved.vibe }
        if selectedAdventure == nil, !saved.adventure.isEmpty { selectedAdventure = saved.adventure }
        if selectedDislikes.isEmpty, !saved.dislikes.isEmpty { selectedDislikes = Set(saved.dislikes) }

        if goToBeers.isEmpty {
            goToBeers = Set(TastePreferences.savedKnownBeers).intersection(Set(onboardingBeerOptions))
        }
        if goToStyles.isEmpty {
            goToStyles = Set(saved.goToStyles.compactMap { BeerStyle(rawValue: $0) })
        }
        // Saved avoid picks are a mixed list: style rawValues split back into
        // style chips, known beer options back into beer chips.
        let savedAvoidPicks = TastePreferences.savedAvoidBeers
        if avoidStyles.isEmpty {
            avoidStyles = Set(savedAvoidPicks.compactMap { BeerStyle(rawValue: $0) })
        }
        if avoidBeers.isEmpty {
            avoidBeers = Set(savedAvoidPicks).intersection(Set(onboardingBeerOptions))
        }
    }

    /// Write-through on every selection change — same semantics as the quiz,
    /// so answers survive swiping the sheet away without tapping Done.
    private func persistAnswers() {
        TastePreferences.save(
            vibe: selectedVibe ?? "",
            adventure: selectedAdventure ?? "",
            dislikes: selectedDislikes.joined(separator: ",")
        )
    }
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(DrinkStore())
            .environmentObject(ScanStore())
            .environmentObject(JournalStore())
    }
}
