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

    /// Versioned export of the effective history rather than the legacy Drink
    /// file. This keeps Journal edits/deletes authoritative in user exports.
    private struct BeerHistoryExport: Codable {
        let schemaVersion: Int
        let exportedAt: Date
        let records: [BeerHistoryExportRecord]
    }

    private struct BeerHistoryExportRecord: Codable {
        let id: UUID
        let name: String
        let brewery: String
        let style: String
        let reaction: String
        let stars: Int?
        let abv: Double?
        let serving: String?
        let notes: String?
        let date: Date
        let source: String
    }
    @State private var exportItem: ExportItem?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var librarySnapshot: BeerLibrarySnapshot {
        BeerLibrarySnapshot(
            journalRecords: journalStore.syncRecords,
            legacyDrinks: drinkStore.drinks,
            scans: scanStore.scans
        )
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

                Section {
                    NavigationLink {
                        DeveloperScenarioLabView { scenario in
                            scenario.apply(
                                drinkStore: drinkStore,
                                scanStore: scanStore,
                                journalStore: journalStore
                            )
                            dismiss()
                        }
                    } label: {
                        Label("Open SipCheck Lab", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityIdentifier("developerScenarioLabLink")
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Launch deterministic app states without touching real data.")
                }
                #endif

                // MARK: - Taste
                Section {
                    Button("Edit taste preferences") {
                        showingTasteEditor = true
                    }
                } header: {
                    Text("Taste")
                }

                // MARK: - Onboarding Lab (founder feedback loop — remove before public App Store release)
                #if DEBUG
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
                #endif

                // MARK: - Notifications
                Section {
                    Toggle(isOn: $followUpNotificationsEnabled) {
                        Text("Follow-up reminders")
                    }
                    .accessibilityIdentifier("followUpRemindersToggle")
                    .onChange(of: followUpNotificationsEnabled) { _, enabled in
                        if !enabled {
                            NotificationService.shared.cancelAllFollowUps()
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
                    .accessibilityIdentifier("replayOnboardingButton")
                    .alert("Replay Onboarding?", isPresented: $showResetOnboardingAlert) {
                        Button("Replay", role: .destructive) {
                            // Replay clears prior reminders and restores the
                            // app trigger without changing iOS permission.
                            followUpNotificationsEnabled = true
                            NotificationService.shared.resetForOnboardingReplay()

                            // Dismiss this sheet first; if we flip the flags while the
                            // sheet is up, the RootView swap happens underneath it and
                            // never becomes visible. Flip them after dismissal settles.
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                hasConfirmedAge = false
                                hasCompletedOnboarding = false
                            }
                        }
                        .accessibilityIdentifier("confirmReplayOnboardingButton")
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
                    #if DEBUG
                    Button("Seed Sample Data") {
                        drinkStore.seedSampleData()
                        scanStore.seedSampleData()
                        journalStore.seedSampleData()
                    }
                    #endif
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
                    NavigationLink("Beer artwork credits") {
                        BeerArtworkCreditsView()
                    }
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
        let export = BeerHistoryExport(
            schemaVersion: 2,
            exportedAt: Date(),
            records: librarySnapshot.tasteRecords.map(exportRecord)
        )
        guard let data = try? encoder.encode(export) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.json")
        try? data.write(to: tempURL)
        exportItem = ExportItem(url: tempURL)
    }

    private func exportAsCSV() {
        var csv = "Name,Brewery,Style,Reaction,Stars,ABV,Serving,Notes,Date,Source\n"
        for record in librarySnapshot.tasteRecords {
            let fields = [
                record.name,
                record.brewery,
                record.style,
                record.rating.displayName,
                record.stars.map(String.init) ?? "",
                record.abv.map { String(format: "%.1f", $0) } ?? "",
                record.drinkType?.displayName ?? "",
                record.notes ?? "",
                ISO8601DateFormatter().string(from: record.date),
                record.source.rawValue
            ]
            csv += fields.map(csvField).joined(separator: ",") + "\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportItem = ExportItem(url: tempURL)
    }

    private func exportRecord(_ record: BeerTasteRecord) -> BeerHistoryExportRecord {
        BeerHistoryExportRecord(
            id: record.id,
            name: record.name,
            brewery: record.brewery,
            style: record.style,
            reaction: record.rating.rawValue,
            stars: record.stars,
            abv: record.abv,
            serving: record.drinkType?.rawValue,
            notes: record.notes,
            date: record.date,
            source: record.source.rawValue
        )
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

#if DEBUG
private struct DeveloperScenarioLabView: View {
    let onLaunch: (DeveloperScenario) -> Void

    private var isIsolatedStorage: Bool {
        ProcessInfo.processInfo.arguments.contains("--isolated-storage")
    }

    var body: some View {
        List {
            if !isIsolatedStorage {
                Section {
                    Label("Protected", systemImage: "lock.shield.fill")
                        .foregroundColor(SipColors.warning)
                    Text("Scenarios only run in isolated storage. Start one with ./scripts/dev run <scenario>.")
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.textSecondary)
                }
            }

            Section {
                ForEach(DeveloperScenario.allCases) { scenario in
                    Button {
                        onLaunch(scenario)
                    } label: {
                        HStack(spacing: SipSpacing.m) {
                            Image(systemName: scenario.symbol)
                                .frame(width: 28)
                                .foregroundColor(SipColors.accent)
                            VStack(alignment: .leading, spacing: SipSpacing.xs) {
                                Text(scenario.title)
                                    .font(SipTypography.headline)
                                    .foregroundColor(SipColors.textPrimary)
                                Text(scenario.subtitle)
                                    .font(SipTypography.caption)
                                    .foregroundColor(SipColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(SipColors.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isIsolatedStorage)
                    .accessibilityIdentifier("developerScenario.\(scenario.rawValue)")
                }
            } header: {
                Text("Scenarios")
            } footer: {
                Text("Each launch replaces only the isolated sandbox and opens the most useful tab.")
            }
        }
        .navigationTitle("SipCheck Lab")
        .accessibilityIdentifier("developerScenarioLab")
    }
}
#endif

private struct BeerArtworkCredit: Identifiable {
    let beer: String
    let attribution: String
    let source: String
    let licenseName: String?
    let license: String?

    var id: String { beer }
}

private struct BeerArtworkCreditsView: View {
    private let credits: [BeerArtworkCredit] = [
        BeerArtworkCredit(
            beer: "Modelo",
            attribution: "Cerveceria Modelo - public domain text logo",
            source: "https://commons.wikimedia.org/wiki/File:Modelo_especial.jpg",
            licenseName: nil,
            license: nil
        ),
        BeerArtworkCredit(
            beer: "Corona",
            attribution: "Public domain simple logo",
            source: "https://commons.wikimedia.org/wiki/File:Corona_Extra_text_logo.svg",
            licenseName: nil,
            license: nil
        ),
        BeerArtworkCredit(
            beer: "Heineken",
            attribution: "Public domain simple logo",
            source: "https://commons.wikimedia.org/wiki/File:Heineken_Logo.svg",
            licenseName: nil,
            license: nil
        ),
        BeerArtworkCredit(
            beer: "Blue Moon",
            attribution: "Aneil Lutchman, 'Blue Moon Beer' - resized",
            source: "https://commons.wikimedia.org/wiki/File:Blue_Moon_Beer.jpg",
            licenseName: "CC BY-SA 2.0",
            license: "https://creativecommons.org/licenses/by-sa/2.0/"
        ),
        BeerArtworkCredit(
            beer: "Sam Adams",
            attribution: "Public domain simple logo",
            source: "https://commons.wikimedia.org/wiki/File:Samuel_Adams_logo.svg",
            licenseName: nil,
            license: nil
        ),
        BeerArtworkCredit(
            beer: "Guinness",
            attribution: "Evanodunaigh, 'Guinness-Logo-1' - unmodified",
            source: "https://commons.wikimedia.org/wiki/File:Guinness-Logo-1.png",
            licenseName: "CC BY-SA 4.0",
            license: "https://creativecommons.org/licenses/by-sa/4.0/"
        ),
        BeerArtworkCredit(
            beer: "Sierra Nevada",
            attribution: "SteveR, 'Sierra Nevada Pale Ale' - resized",
            source: "https://commons.wikimedia.org/wiki/File:Sierra_Nevada_Pale_Ale.jpg",
            licenseName: "CC BY 2.0",
            license: "https://creativecommons.org/licenses/by/2.0/"
        ),
        BeerArtworkCredit(
            beer: "Lagunitas",
            attribution: "Public domain simple logo",
            source: "https://commons.wikimedia.org/wiki/File:Lagunitas-logo-2017.png",
            licenseName: nil,
            license: nil
        ),
        BeerArtworkCredit(
            beer: "Two Hearted Ale",
            attribution: "edwin, 'Bell's Two Hearted Ale' - resized",
            source: "https://commons.wikimedia.org/wiki/File:Bell%27s_Two_Hearted_Ale.jpg",
            licenseName: "CC BY 2.0",
            license: "https://creativecommons.org/licenses/by/2.0/"
        ),
        BeerArtworkCredit(
            beer: "Coors Light",
            attribution: "Public domain simple logo",
            source: "https://commons.wikimedia.org/wiki/File:Coors_Light_logo.svg",
            licenseName: nil,
            license: nil
        ),
        BeerArtworkCredit(
            beer: "Bud Light",
            attribution: "Sarah Stierch, 'Bud Light - June 2024' - resized",
            source: "https://commons.wikimedia.org/wiki/File:Bud_Light_-_June_2024_-_Sarah_Stierch.jpg",
            licenseName: "CC BY 4.0",
            license: "https://creativecommons.org/licenses/by/4.0/"
        ),
        BeerArtworkCredit(
            beer: "Stella Artois",
            attribution: "Stella Artois UK / AB InBev, 'Stella Artois current logo 2015' - unmodified",
            source: "https://commons.wikimedia.org/wiki/File:Stella_Artois_current_logo_2015.png",
            licenseName: "CC BY 3.0",
            license: "https://creativecommons.org/licenses/by/3.0/"
        ),
        BeerArtworkCredit(
            beer: "Allagash White",
            attribution: "Allagash Brewing, 'Allagash White' - resized",
            source: "https://www.flickr.com/photos/89562459@N03/36639521043",
            licenseName: "CC BY 2.0",
            license: "https://creativecommons.org/licenses/by/2.0/"
        ),
        BeerArtworkCredit(
            beer: "Dogfish Head",
            attribution: "Terry Lucas, 'Happy Saturday (cropped)' - resized",
            source: "https://commons.wikimedia.org/wiki/File:Happy_Saturday_(238576229)_(cropped).jpeg",
            licenseName: "CC BY 3.0",
            license: "https://creativecommons.org/licenses/by/3.0/"
        ),
        BeerArtworkCredit(
            beer: "Stone IPA",
            attribution: "@joefoodie, 'Stone IPA' - resized",
            source: "https://www.flickr.com/photos/98178986@N00/2537689794",
            licenseName: "CC BY 2.0",
            license: "https://creativecommons.org/licenses/by/2.0/"
        ),
        BeerArtworkCredit(
            beer: "Goose Island",
            attribution: "Ruth Hartnup, 'Goose Island Beer Co. logo' - resized",
            source: "https://commons.wikimedia.org/wiki/File:Goose_Island_Beer_Co._logo_(31478241163).jpg",
            licenseName: "CC BY 2.0",
            license: "https://creativecommons.org/licenses/by/2.0/"
        )
    ]

    var body: some View {
        List {
            Section {
                ForEach(credits) { credit in
                    VStack(alignment: .leading, spacing: SipSpacing.xs) {
                        Text(credit.beer)
                            .font(SipTypography.headline)
                        Text(credit.attribution)
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textSecondary)
                        HStack(spacing: SipSpacing.m) {
                            Link("Source", destination: URL(string: credit.source)!)
                            if let licenseName = credit.licenseName,
                               let license = credit.license {
                                Link(licenseName, destination: URL(string: license)!)
                            }
                        }
                        .font(SipTypography.subhead)
                    }
                    .padding(.vertical, SipSpacing.xs)
                }
            } footer: {
                Text("CC-licensed photos were resized and recompressed for SipCheck. Adapted files remain under the listed licenses. All trademarks belong to their owners.")
            }
        }
        .navigationTitle("Artwork Credits")
        .navigationBarTitleDisplayMode(.inline)
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
                    // Go-to / stay-away grids first: they're the default
                    // flow's primary taste signals. The two answers stay
                    // independently editable; the scorer gives a hard avoid
                    // precedence if the same pick appears in both.
                    VStack(alignment: .leading, spacing: SipSpacing.m) {
                        Text("Your go-tos")
                            .font(SipTypography.headline)
                            .foregroundColor(SipColors.textPrimary)
                        OnboardingPreferencePicker(
                            selectedBeers: goToBeers,
                            selectedStyles: goToStyles,
                            beerAccessibilityPrefix: "settingsGoToBeerTile",
                            styleAccessibilityPrefix: "settingsGoToStyle",
                            modeAccessibilityID: "settingsGoToMode",
                            searchAccessibilityID: "settingsGoToSearch",
                            onToggleBeer: toggleGoToBeer,
                            onToggleStyle: toggleGoToStyle
                        )
                    }

                    VStack(alignment: .leading, spacing: SipSpacing.m) {
                        Text("Your stay-aways")
                            .font(SipTypography.headline)
                            .foregroundColor(SipColors.textPrimary)
                        OnboardingPreferencePicker(
                            selectedBeers: avoidBeers,
                            selectedStyles: avoidStyles,
                            beerAccessibilityPrefix: "settingsAvoidBeerTile",
                            styleAccessibilityPrefix: "settingsAvoidStyle",
                            modeAccessibilityID: "settingsAvoidMode",
                            searchAccessibilityID: "settingsAvoidSearch",
                            onToggleBeer: toggleAvoidBeer,
                            onToggleStyle: toggleAvoidStyle
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
                }
                .padding(.horizontal, SipSpacing.xl)
                .padding(.top, SipSpacing.m)
                .padding(.bottom, SipSpacing.xl)
            }
            .background(SipColors.background.ignoresSafeArea())
            .navigationTitle("Taste Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tastePreferencesDoneButton")
                }
            }
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

    // MARK: Go-to / stay-away tap handlers (write-through on every tap,
    // matching the onboarding pages — swiping the sheet away must not
    // discard edits)

    private func toggleGoToStyle(_ style: BeerStyle) {
        if goToStyles.contains(style) { goToStyles.remove(style) } else { goToStyles.insert(style) }
        persistGoTo()
    }

    private func toggleGoToBeer(_ beer: String) {
        if let existing = goToBeers.first(where: { BeerMatcher.exactNamesMatch($0, beer) }) {
            goToBeers.remove(existing)
        } else {
            goToBeers.insert(beer)
        }
        persistGoTo()
    }

    private func toggleAvoidStyle(_ style: BeerStyle) {
        if avoidStyles.contains(style) { avoidStyles.remove(style) } else { avoidStyles.insert(style) }
        persistAvoid()
    }

    private func toggleAvoidBeer(_ beer: String) {
        if let existing = avoidBeers.first(where: { BeerMatcher.exactNamesMatch($0, beer) }) {
            avoidBeers.remove(existing)
        } else {
            avoidBeers.insert(beer)
        }
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
        TastePreferences.saveGoToSelections(beers: beers, styleChips: styleChips)

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                TastePreferences.locallyResolvedStyles(for: beers)
            }.value
            guard generation == goToGeneration,
                  TastePreferences.goToSelectionsAreCurrent(
                    beers: beers,
                    styleChips: styleChips
                  ) else { return }
            TastePreferences.saveGoTo(beers: beers, styleChips: styleChips, seedStyles: styles)
        }
    }

    /// Mirror of StayAwayPickerPage.persistAvoidSelections: raw picks (mixed
    /// beer names + style rawValues) plus the styles they resolve to — the
    /// scorer's avoid channel consumes the resolved styles.
    private func persistAvoid() {
        avoidGeneration += 1
        let generation = avoidGeneration
        let beers = avoidBeers.sorted()
        let styleChips = avoidStyles.map(\.rawValue).sorted()
        TastePreferences.saveAvoidSelections(beers: beers, styleChips: styleChips)

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                Array(Set(styleChips).union(TastePreferences.locallyResolvedStyles(for: beers))).sorted()
            }.value
            guard generation == avoidGeneration,
                  TastePreferences.avoidSelectionsAreCurrent(
                    beers: beers,
                    styleChips: styleChips
                  ) else { return }
            TastePreferences.saveAvoidSelections(
                beers: beers,
                styleChips: styleChips,
                avoidStyles: styles
            )
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
            goToBeers = Set(TastePreferences.savedGoToBeers)
        }
        if goToStyles.isEmpty {
            goToStyles = Set(TastePreferences.savedGoToStyles.compactMap { BeerStyle(rawValue: $0) })
        }
        if avoidStyles.isEmpty {
            avoidStyles = Set(TastePreferences.savedAvoidStyleChips.compactMap { BeerStyle(rawValue: $0) })
        }
        if avoidBeers.isEmpty {
            avoidBeers = Set(TastePreferences.savedAvoidBeers)
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
